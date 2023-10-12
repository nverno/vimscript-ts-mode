echo
  "\ comment
  \ "hello, world"

func foo(
  "\ a ludicrously long but necessary description that won't fit
  \ first_argument_with_a_long_name,
  "\ another ludicrously long but necessary description that won't fit
  \ second_argument_with_a_long_name)
  "\ if you don't include this the function will run even after an error
  \ abort
  return first_argument_with_a_long_name + second_argument_with_a_long_name
endfunc

let x =<< END
  "\ this is not a comment
END

let array = [
  "\ first entry comment
  \ 'first',
  "\ second entry comment
  \ 'second',
  \ ]
