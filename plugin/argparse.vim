
command! -nargs=1 -bang Parse echo scripting#parser#parse(<q-args>, {'[KMAP]':{'v':'verbose'}, '[CONTEXT]':(<bang>0?b: : {})})
"Parse --a=3 --b<=$SHELL --c=$HOME git -m'a b c'
"[{'a': '3', 'b': 'zsh', 'c': '$HOME', 'm': 'a b c'}, ['git']]

" examples


command! -bang -range=-1 -nargs=1 Append call argparse#example#append_cmd(<q-args>, <count>, <line1>, <line2>, <bang>0)
