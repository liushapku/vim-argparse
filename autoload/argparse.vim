if !has('python3') && !has('python')
  echomsg 'argparse requires python or python3'
  finish
elseif exists('g:loaded_argparse') && !exists('g:dev_argparse')
  finish
endif


let argparse#delimiters = '~!@#$%^:,./''"'
let argparse#default = '1-DEFAULT-'  " when used as int/bool, it will be 1

" used by argparse#transformer eval functions, the variables in this
" dict can be directly accessed (this dict is merged into l:)
let s:context = {}
fu! argparse#_get_context()
  return s:context
endfu
fu! argparse#_current_opts()
  return s:current_opts
endfu

" any number is equivalent to {x->x}
" a char not in this dict will be used to split the var
" (valid chars: see argparse#delimiters)
"   --a,1,2,3 => a=['1','2','3']
let s:transformers = {}
let s:transformers['' ] = 0 " any number keeps var not transformed
let s:transformers['='] = 0 " any number keeps var not transformed
let s:transformers['<'] = {x-> expand(x)} " --a<$SHELL => a='zsh'   --a=$SHELL => a='$SHELL'
" eval var as an expression. s:context (which is set to the 'meta' parameter) is merged into l:
" ex: Parse! --a(did_ftplugin => (Parse! will have b: as context) a will be set
"        to b:did_ftplugin
"     --a(3*10 => a = 30
let s:transformers['('] = function('argparse#transformer#eval')
" transform to a function:
" --a)len => a = function('len')
" --a){x->x*3} => a is the lambda {x->x*3}
let s:transformers[')'] = function('argparse#transformer#func')
" split on , and eval each item (to only split into list of strings use a char
" not in s:transformers keys
" --a[1,2,3 => a = [1,2,3]
let s:transformers['['] = function('argparse#transformer#list_eval')
" like argparse#tranformer#dict, but turn each value into a func
" --funcs]a:len => funcs = {'a': function('len')}
let s:transformers[']'] = function('argparse#transformer#dict_func')
" like argparse#transformer#dict, but eval each value
" --d{a:1,b:2  => d={'a':1, 'b':2}
let s:transformers['{'] = function('argparse#transformer#dict_eval')
" eval into a dict
" --d{a:1,b:2  => d={'a':'1', 'b':'2'}
let s:transformers['}'] = function('argparse#transformer#dict')
" replace '@' with ' '. for supplying string containing space
" If string contains '@', use '#' below
" --a@1@2@3  => a='1 2 3'
let s:transformers['@'] = {x-> substitute(x, '@', ' ', 'g')}
" replace '#' with ' '. for supplying string containing space
" If string contains '#', use '@' above
" --a#1#2#3  => a='1 2 3'
let s:transformers['#'] = {x-> substitute(x, '#', ' ', 'g')} " ex: --a@1@2@3 => a='1 2 3'  --a@#@! => a='# !'
" to quote the variable
" --a\'abc => a[0], = "'" a[1] = 'a', ...
let s:transformers["'"] = {x-> string(x)} " to quote x: --a\'abc => a is "'abc'"
" to quote the variable
" --a\"abc => a[0], = "'" a[1] = 'a', ...
let s:transformers['"'] = {x-> string(x)}

" transform a:var according to a:type
" 1. if a:type is a string, it will be looked up in the dict s:transformers
"    if found in the dict: the value will be used as transformer
"    otherwise, itself will be used as transformer
" 2. a. if the transformer is a func, it is applied to a:var
"    b. if the transformer is a dict, it is treated as a callable object
"       (has a key 'call' with value of func type), this func is applied to a:var
"    c. if the transformer is a number, then a:var is returned
"    d. if the transformer is a string, then split(a:var, '\V'. the_string) is returned
fu! s:transform(type, var) abort
  if type(a:type) == v:t_string
    let l:F = get(s:transformers, a:type, a:type)
  else
    let l:F = a:type
  endif
  let type = type(l:F)
  if type == v:t_func
    return l:F(a:var)
  elseif type == v:t_dict
    return l:F.call(a:var)
  elseif type == v:t_number
    return a:var
  elseif type == v:t_string
    if l:F == ''
      let l:F = a:type
    endif
    return split(a:var, '\V'. l:F, 1)
  endif
endfu

let s:word = '[-a-zA-Z0-9]'
let s:leader = '[a-zA-Z0-9]'
let s:symbol = printf('%s%s*', s:leader, s:word)
let s:types = printf('[][(){}<>=%s]', g:argparse#delimiters)

" use %% in printf to denote %
let s:pat_long = printf('\v^\s*\-([-+*])(%s)((%s)(.*))?$', s:symbol, s:types)
" s:pat_long tokens: - append_char symbol [type char] value
" where append_char is - or + or *
"    if it is -: then set var as is
"    if it is +: then append var to a list
"    if it is *: then extend var (should be list or dict) to existing list or dict
" where [type char]:
"    see s:transformers' keys with exception for '=', which
"    will use the type from [TYPE] meta dict for this symbol if it exists
let s:pat_short = printf('\v^\s*-(%s)(.*)$', s:leader)  " no types allowed,
" s:pat_short tokens: - leader value
let s:pat_positional = printf('\v^\s*(.{-})(\?(\?)?(%s)?)?$', s:types)

" syntax: argparse(qargs, [meta], [default_opts])
" starting whitespaces are trimmed, ending whitespaces are kept
" TRY: Parse and Parse! command
"
" # meta: a dict
" [key] represents meta-option, which affects how parser interprets the args
" other keys in meta will be set as the eval context
"
" known mega-options:
" -- [KMAP]: the map from --key or -key to the destination option
"            for example: [KMAP] = {'v': 'verbose'}, so that -v1 is equiv to --verbose=1
" -- [IFS]: field separator to tokenize the a:qargs.
"           If emtpy, then use python shlex.split, otherwise use vim split()
" -- [CONTEXT]: dict. used to evaluate the expression if transformer is eval or list_eval, etc
"               'a' is used to access member 'a' (NOTE: _.a is used to access the current option a)
"               ex: let g:x = 100
"                   argparse('-ax --b=_.a*g:x', {'[CONTEXT]': {'x': 3}, '[TYPE]': {'a':'(', 'b':'('}})
"                   will cause a and b to be transformed using argparse#transformer#eval
"                   then 'a' will be 3 since in CONTEXT x is 3, 'b' will be 300 since when 'b' is parsed
"                   'a' is 3 and 'b' is 'a*g:x' (note the use of '_.a')
" -- [POSITIONAL]: if 'auto', then all args after the first positional
"                  arg are treaded as positional args
"                  if 'all', then all args are positional
"                  if 'none', then no args should be positional
"                  otherwise, positional args can be any where, after '--'
"                  they are all treated as positional (default)
" -- [TYPE]: dict, the default type of an option. Use key '_' to set default type for
"                  positional args. see s:transform
" -- [NAMES]: list of string or string (which will be turned into a list by splitting at ',')
"             this defines the glob patterns that every option name should at least match one of them
"             otherwise the option will be invalid
"
" return:
" 1. if POSITIONAL is 'none': returns the options as a dict
" 2. if POSITIONAL is 'all' : returns the positional args as a list
" 3. otherwise:               returns [opts, positional]
"
fu! argparse#parse(qargs, ...) abort
  let meta = copy(get(a:000, 0, {}))
  let opts = copy(get(a:000, 1, {}))
  if type(meta) != v:t_dict || type(opts) != v:t_dict
    throw 'a:0 and a:1 should be dict. a:0 is the meta data, a:1 is the default opts'
  endif
  let keymap = argparse#utils#pop(meta, '[KMAP]', {})
  let positionalmode = argparse#utils#pop(meta, '[POSITIONAL]', '')
  let IFS = argparse#utils#pop(meta, '[IFS]', '')
  let context = argparse#utils#pop(meta, '[CONTEXT]', {})
  let default_modes = argparse#utils#pop(meta, '[TYPE]', {})
  let valid_keys = argparse#utils#pop(meta, '[NAMES]', 0)
  if type(valid_keys) == v:t_string
    let valid_keys = split(valid_keys, ',')
  endif
  let last_mode = get(default_modes, '_', '') " last positional mode
  call extend(meta, context, 'keep')
  let s:context = meta
  let s:current_opts = opts

  let args = argparse#split(a:qargs, IFS)
  if positionalmode != 'all'
    let lst = []
    for idx in range(len(args))
      let x = args[idx]
      if x =~ s:pat_long
        let [append, key, varpt, Type, var] = matchlist(x, s:pat_long)[1:5]
        let key = get(keymap, key, key)
        if Type == '='
          let Type = get(default_modes, key, Type)
        endif
        call s:add_opt(valid_keys, opts, key, varpt, append, Type, var)
      elseif x =~ s:pat_short
        let [key, var] = matchlist(x, s:pat_short)[1:2]
        let key = get(keymap, key, key)
        let types = get(default_modes, key, '')
        let append = '-'
        call s:add_opt(valid_keys, opts, key, var, append, types, var)
      else
        if x =~ '^\s*--$'
          let lst = args[idx+1:]
          break
        elseif positionalmode == 'auto'
          let lst = args[idx:]
          break
        else
          call add(lst, x)
        endif
      endif
    endfor
  else
    let lst = args
  endif
  if positionalmode == 'none' && len(lst) != 0
    throw 'parse: positional type is "none" but positional args exist'
  endif

  let args = []
  for x in lst
    let matched = matchlist(x, s:pat_positional)
    let [var, hasmodes, savemodes, types] = matched[1:4]
    if hasmodes == ''
      let types = last_mode
    elseif savemodes == '?'
      let last_mode = types
    endif
    call add(args, s:transform(types, var))
  endfor
  if get(opts, 'verbose', 0) || get(opts, 'v', 0)
    echomsg "Args:" string(opts) string(args)
  endif
  if positionalmode == 'none'
    return opts
  elseif positionalmode == 'all'
    return args
  else
    return [opts, args]
  endif
endfu

" positional parameters: [IFS] [keepempty]
fu! argparse#split(str, ...)
  let IFS = get(a:000, 0, '')
  let IFS = IFS==''?get(g:, 'IFS', ''):IFS
  if IFS == ''
    if has('python3')
      py3 import vim, shlex
      py3 rv = shlex.split(vim.eval('a:str'))
      return py3eval('rv')
    else
      py import vim, shlex
      py rv = shlex.split(vim.eval('a:str'))
      return pyeval('rv')
    endif
  else
    let keepempty = get(a:000, 1, 0)
    " only get one character
    let rv = split(a:str, printf('%s', IFS), keepempty)
    return rv
  endif
endfu

fu! argparse#quote(str)
  if has('python3')
    py3 import vim, shlex
    py3 rv = shlex.quote(vim.eval('a:str'))
    return py3eval('rv')
  else
    py import vim, shlex
    py rv = shlex.quote(vim.eval('a:str'))
    return pyeval('rv')
  endif
endfu

fu! s:valid(valid_keys, key)
  if a:valid_keys is 0
    return 1
  endif
  for pat in a:valid_keys
    let pat = glob2regpat(pat)
    if a:key =~ pat
      return 1
    endif
  endfor
  return 0
endfu

" valid_keys: a list of pattern that defines the valid opt names
" opts:
" key: opt name
" varpart:
" append: - or + or *, the char after dash:
"   -oa:  set o to a
"   --opt=x: set opt to x
"   -+opt=x: append x to the list:
"       --opt=1 -+opt=2 => opt will be [1, 2] (the same as -+opt=1 -+opt=2)
"   -*opt=x: extend x (should be transformed into a list or dict) to existing
"            list or dict (use argparse#transformer#dict etc)
fu! s:add_opt(valid_keys, opts, key, varpart, append, type, var)
  let key = substitute(a:key, '-', '_', 'g')
  if !s:valid(a:valid_keys, key)
    throw printf('key %s is not acceptable', key)
  endif
  40Log key a:varpart a:append a:type a:var
  let Var = a:varpart == '' ? g:argparse#default : s:transform(a:type, a:var)
  if a:append == '-' || a:append == ''
    let a:opts[key] = Var
    return
  elseif !has_key(a:opts, key)
    if a:append == '+'
      let a:opts[key] = [Var]
    else
      let a:opts[key] = Var
    endif
    return
  endif

  let tp = type(a:opts[key])
  let vtp = type(Var)
  if a:append == '+'
    " if already exists this key but not a list, wrap it in a list
    if tp != v:t_list
      let a:opts[key] = [a:opts[key]]
    endif
    call add(a:opts[key], Var)
    return
  elseif a:append == '*'
    if vtp == v:t_list && tp != v:t_list
      let a:opts[key] = [a:opts[key]]
    endif
    let tpnew = type(Var)
    let tpold = type(a:opts[key])
    if tpnew == tpold && (tpnew == v:t_list || tpnew == v:t_dict)
      call extend(a:opts[key], Var)
    else
      throw printf('parser: cannot extend type %s with type %s', tpold, tpnew)
    endif
  else
    throw 'parser: unexpected append type:' a:append
  endif
endfu

" parse args and call funcname(opts, positionals)
fu! argparse#call(funcname, ...)
  try
    let args = call('argparse#parse', a:000)
    if type(args) == v:t_dict  " [POSITIONAL] is 'none'
      let args = [args]
    endif
    return call(a:funcname, args)
  catch
    if exists(':Throw')
      Throw
    else
      throw printf('%s in %s', v:exception, v:throwpoint)
    endif
  endtry
endfu

