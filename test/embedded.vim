" (lua_statement (chunk))
lua require('config/treesitter')

" (ruby_statement (chunk))
ruby puts("foo")

" absdcasd fasdkfasdf
function! s:update_ruby()
  " (ruby_statement (script (body)))
  ruby << EOF
module PlugStream
  SEP = [
    "\r",
    "\n",
    nil
  ]
  def get_line
    buffer = ''
    loop do
      char = readchar rescue return
      if SEP.include? char.chr
        buffer << $/
        break
      else
        buffer << char
      end
    end
    buffer
  end
end unless defined?(PlugStream)

def esc arg
  %["#{arg.gsub('"', '\"')}"]
end

def killall pid
  pids = [pid]
  if /mswin|mingw|bccwin/ =~ RUBY_PLATFORM
    pids.each { |pid| Process.kill 'INT', pid.to_i rescue nil }
  else
    unless `which pgrep 2> /dev/null`.empty?
      children = pids
      until children.empty?
        children = children.map { |pid|
          `pgrep -P #{pid}`.lines.map { |l| l.chomp }
        }.flatten
        pids += children
      end
    end
    pids.each { |pid| Process.kill 'TERM', pid.to_i rescue nil }
  end
end

def compare_git_uri a, b
  regex = %r{^(?:\w+://)?(?:[^@/]*@)?([^:/]*(?::[0-9]*)?)[:/](.*?)(?:\.git)?/?$}
  regex.match(a).to_a.drop(1) == regex.match(b).to_a.drop(1)
end

require 'thread'
require 'fileutils'
require 'timeout'
running = true
iswin = VIM::evaluate('s:is_win').to_i == 1
pull  = VIM::evaluate('s:update.pull').to_i == 1
base  = VIM::evaluate('g:plug_home')
all   = VIM::evaluate('s:update.todo')
limit = VIM::evaluate('get(g:, "plug_timeout", 60)')
tries = VIM::evaluate('get(g:, "plug_retries", 2)') + 1
nthr  = VIM::evaluate('s:update.threads').to_i
maxy  = VIM::evaluate('winheight(".")').to_i
vim7  = VIM::evaluate('v:version').to_i <= 703 && RUBY_PLATFORM =~ /darwin/
cd    = iswin ? 'cd /d' : 'cd'
tot   = VIM::evaluate('len(s:update.todo)') || 0
bar   = ''
skip  = 'Already installed'
mtx   = Mutex.new
take1 = proc { mtx.synchronize { running && all.shift } }
logh  = proc {
  cnt = bar.length
  $curbuf[1] = "#{pull ? 'Updating' : 'Installing'} plugins (#{cnt}/#{tot})"
  $curbuf[2] = '[' + bar.ljust(tot) + ']'
  VIM::command('normal! 2G')
  VIM::command('redraw')
}
where = proc { |name| (1..($curbuf.length)).find { |l| $curbuf[l] =~ /^[-+x*] #{name}:/ } }
log   = proc { |name, result, type|
  mtx.synchronize do
    ing  = ![true, false].include?(type)
    bar += type ? '=' : 'x' unless ing
    b = case type
        when :install  then '+' when :update then '*'
        when true, nil then '-'
        else
          VIM::command("call add(s:update.errors, '#{name}')")
          'x'
        end
    result =
      if type || type.nil?
        ["#{b} #{name}: #{result.lines.to_a.last || 'OK'}"]
      elsif result =~ /^Interrupted|^Timeout/
        ["#{b} #{name}: #{result}"]
      else
        ["#{b} #{name}"] + result.lines.map { |l| "    " << l }
      end
    if lnum = where.call(name)
      $curbuf.delete lnum
      lnum = 4 if ing && lnum > maxy
    end
    result.each_with_index do |line, offset|
      $curbuf.append((lnum || 4) - 1 + offset, line.gsub(/\e\[./, '').chomp)
    end
    logh.call
  end
}
bt = proc { |cmd, name, type, cleanup|
  tried = timeout = 0
  begin
    tried += 1
    timeout += limit
    fd = nil
    data = ''
    if iswin
      Timeout::timeout(timeout) do
        tmp = VIM::evaluate('tempname()')
        system("(#{cmd}) > #{tmp}")
        data = File.read(tmp).chomp
        File.unlink tmp rescue nil
      end
    else
      fd = IO.popen(cmd).extend(PlugStream)
      first_line = true
      log_prob = 1.0 / nthr
      while line = Timeout::timeout(timeout) { fd.get_line }
        data << line
        log.call name, line.chomp, type if name && (first_line || rand < log_prob)
        first_line = false
      end
      fd.close
    end
    [$? == 0, data.chomp]
  rescue Timeout::Error, Interrupt => e
    if fd && !fd.closed?
      killall fd.pid
      fd.close
    end
    cleanup.call if cleanup
    if e.is_a?(Timeout::Error) && tried < tries
      3.downto(1) do |countdown|
        s = countdown > 1 ? 's' : ''
        log.call name, "Timeout. Will retry in #{countdown} second#{s} ...", type
        sleep 1
      end
      log.call name, 'Retrying ...', type
      retry
    end
    [false, e.is_a?(Interrupt) ? "Interrupted!" : "Timeout!"]
  end
}
main = Thread.current
threads = []
watcher = Thread.new {
  if vim7
    while VIM::evaluate('getchar(1)')
      sleep 0.1
    end
  else
    require 'io/console' # >= Ruby 1.9
    nil until IO.console.getch == 3.chr
  end
  mtx.synchronize do
    running = false
    threads.each { |t| t.raise Interrupt } unless vim7
  end
  threads.each { |t| t.join rescue nil }
  main.kill
}
refresh = Thread.new {
  while true
    mtx.synchronize do
      break unless running
      VIM::command('noautocmd normal! a')
    end
    sleep 0.2
  end
} if VIM::evaluate('s:mac_gui') == 1

clone_opt = VIM::evaluate('s:clone_opt').join(' ')
progress = VIM::evaluate('s:progress_opt(1)')
nthr.times do
  mtx.synchronize do
    threads << Thread.new {
      while pair = take1.call
        name = pair.first
        dir, uri, tag = pair.last.values_at *%w[dir uri tag]
        exists = File.directory? dir
        ok, result =
          if exists
            chdir = "#{cd} #{iswin ? dir : esc(dir)}"
            ret, data = bt.call "#{chdir} && git rev-parse --abbrev-ref HEAD 2>&1 && git config -f .git/config remote.origin.url", nil, nil, nil
            current_uri = data.lines.to_a.last
            if !ret
              if data =~ /^Interrupted|^Timeout/
                [false, data]
              else
                [false, [data.chomp, "PlugClean required."].join($/)]
              end
            elsif !compare_git_uri(current_uri, uri)
              [false, ["Invalid URI: #{current_uri}",
                       "Expected:    #{uri}",
                       "PlugClean required."].join($/)]
            else
              if pull
                log.call name, 'Updating ...', :update
                fetch_opt = (tag && File.exist?(File.join(dir, '.git/shallow'))) ? '--depth 99999999' : ''
                bt.call "#{chdir} && git fetch #{fetch_opt} #{progress} 2>&1", name, :update, nil
              else
                [true, skip]
              end
            end
          else
            d = esc dir.sub(%r{[\\/]+$}, '')
            log.call name, 'Installing ...', :install
            bt.call "git clone #{clone_opt unless tag} #{progress} #{uri} #{d} 2>&1", name, :install, proc {
              FileUtils.rm_rf dir
            }
          end
        mtx.synchronize { VIM::command("let s:update.new['#{name}'] = 1") } if !exists && ok
        log.call name, result, ok
      end
    } if running
  end
end
threads.each { |t| t.join rescue nil }
logh.call
refresh.kill if refresh
watcher.kill
  EOF
endfunction

" adfasdfasdf
" alkdfasdf 
function! f()
  
endfunction
