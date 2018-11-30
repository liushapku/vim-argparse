" TRANSFORMERS:
" '' : 0,
" =: 0,
" <: {x-> expand(x)},
" (: function('argparse#transformer#eval')  --a(3*10 => 30 (note meta is used as eval context)
" ): function('argparse#transformer#func')  --a)len => function('len')
" [: function('argparse#transformer#list_eval') --a[1,2 => [1,2]
" ]: function('argparse#transformer#dict_func') --a]x:len => {'x': function('len')
" {: function('argparse#transformer#dict_eval') --a{x:1,y:2 => {'x':1, y:2}
" }: function('argparse#transformer#dict')   --a}x:1,y:2 => {'x':'1','y':'2'}
" @: {x-> substitute(x, '@', ' ', 'g')} " to handle string containing space
" #: {x-> substitute(x, '#', ' ', 'g')} " to handle string containing space
" ': {x-> string(x)},
" ": {x-> string(x)},
" OTHERS in argparse#delimiters: used to split the var: --a,1,2 => ['1','2']
"
" append mode: - or + or *  (as the second char in --a=1 -+a=1 -*a=1)
" -: use as is
" +: append to list
" *: extend list or dict  (need to transform var to a list or dict using
"    transformers like [/]/{/}
command! -nargs=1 -bang Parse echo argparse#parse(<q-args>, {'[KMAP]':{'v':'verbose'}, '[CONTEXT]':(<bang>0?b: : {})})
" examples
" Parse -a4  ==> [{'a': '4'}, []]
" Parse -a
" Parse --a=3 --b<$SHELL --c=$HOME git -m'a b c' ==> [{'a': '3', 'b': 'zsh', 'c': '$HOME', 'm': 'a b c'}, ['git']]

" an example
command! -bang -range=-1 -nargs=1 Append call argparse#example#append_cmd(<q-args>, <count>, <line1>, <line2>, <bang>0)
