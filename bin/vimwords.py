#!/usr/bin/env python
#
# Dump vim keywords as lisp assoc list
#
# modified from:
# https://github.com/pygments/pygments/blob/master/scripts/get_vimkw.py
import re

r_line = re.compile(
    r"^(syn keyword vimCommand contained|syn keyword vimOption "
    r"contained|syn keyword vimAutoEvent contained)\s+(.*)"
)
r_item = re.compile(r"(\w+)(?:\[(\w+)\])?")


def getkw(input, output):
    out = open(output, "w")
    output_info = {"command": [], "option": [], "auto": []}

    with open(input, "r") as f:
        for line in f:
            m = r_line.match(line)
            if m:
                # decide which output gets mapped to d
                if "vimCommand" in m.group(1):
                    d = output_info["command"]
                elif "AutoEvent" in m.group(1):
                    d = output_info["auto"]
                else:
                    d = output_info["option"]

                # Extract all the shortened versions
                for i in r_item.finditer(m.group(2)):
                    d.append((i.group(1), "%s%s" % (i.group(1), i.group(2) or "")))

    output_info["option"].append(("nnoremap", "nnoremap"))
    output_info["option"].append(("inoremap", "inoremap"))
    output_info["option"].append(("vnoremap", "vnoremap"))

    print("(", file=out)
    for key, keywordlist in output_info.items():
        keywordlist.sort()
        print("(", key, file=out)
        for a, b in keywordlist:
            print(f'("{a}" "{b}")', file=out)
        print(")", file=out)
    print(")", file=out)

    out.close()


def is_keyword(w, keywords):
    for i in range(len(w), 0, -1):
        if w[:i] in keywords:
            return keywords[w[:i]][: len(w)] == w
    return False


def main():
    import argparse

    parser = argparse.ArgumentParser(
        description="Read vim keywords from syntax/vim.vim"
    )
    parser.add_argument("-v", "--version", type=str, help="Vim version", default="8.2")
    parser.add_argument(
        "-o", "--output", type=str, help="Output file name", default="vim-builtins.txt"
    )
    parser.add_argument(
        "-f",
        "--file",
        type=str,
        help="Vim syntax file",
        default=None,
    )
    args = parser.parse_args()
    version = args.version.replace(".", "")
    fname = args.file if args.file else f"/usr/share/vim/vim{version}/syntax/vim.vim"
    getkw(fname, args.output)


if __name__ == "__main__":
    main()
