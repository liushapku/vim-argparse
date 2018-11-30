if !has('python3') && !has('python')
  echomsg 'argparse requires python or python3'
  finish
elseif exists('g:loaded_argparse') && !exists('g:dev_argparse')
  finish
endif
  

let argparse#delimiters = '~!@#$%^:,./''"'
let argparse#default = '1-DEFAULT-'

" number is equivalent to {x->x}
" string is equivalent to split(x, '\V'. the_string)
" if string is empty, the_string is the same as the key
let s:transformers = {
      \ '' : 0,
      \ '=': 0,
      \ '<': {x-> expand(x)},
      \ '>': function('argparse#transformer#call'),
      \ '(': function('argparse#transformer#eval'),
      \ ')': function('argparse#transformer#func'),
      \ '[': function('argparse#transformer#list_eval'),
      \ ']': function('argparse#transformer#dict_func'),
      \ '{': function('argparse#transformer#dict_eval'),
      \ '}': function('argparse#transformer#dict'),
      \ '@': {x-> substitute(x, '@', ' ', 'g')},
      \ '#': {x-> substitute(x, '#', ' ', 'g')},
      \ "'": {x-> string(x)},
      \ '"': {x-> string(x)},
      \ }

let s:context = {}
function! argparse#_get_context()
  return s:context
endfunction
function! argparse#_current_opts()
  return s:current_opts
endfunction

function! s:transform(type, var) abort
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
endfunction

let s:word = '[-a-zA-Z0-9]'
let s:leader = '[a-zA-Z0-9]'
let s:symbol = printf('%s%s*', s:leader, s:word)
let s:types = printf('[][(){}<>=%s]', g:argparse#delimiters)
" use %% in printf to denote %
let s:pat_long = printf('\v^\s*\-([-+*])(%s)((%s)(.*))?$', s:symbol, s:types)
"let s:pat_short = printf('\v^\s*(-)(%s)?(%s)(.*)$', s:types, s:leader)
let s:pat_short = printf('\v^\s*-(%s)(.*)$', s:leader)  " no types allowed
let s:pat_positional = printf('\v^\s*(.{-})(\?(\?)?(%s)?)?$', s:types)
"
" starting whitespaces are trimmed, ending whitespaces are kept
" [key] represents meta-option, which affects how parser interprets the args
" known mega-options:
" -- [KMAP]: the map from --key or -key to the destination option
"            for example: [KMAP] = {'v': 'verbose'}
" -- [IFS]: field separator. if emtpy, then use python shlex.split, otherwise
"           use vim split()
" -- [CONTEXT]: dict. used for $= to evaluate the expression
" -- [POSITIONAL]: if 'auto', then all args after the first positional
"                  arg are treaded as positional args
"                  if 'all', then all args are positional
"                  if 'none', then no args should be positional
"                  otherwise, positional args can be any where, after '--'
"                  they are all treated as positional (default)
" -- [TYPE]: dict, the default type of an option. use key '_' to set for
"                  positional args
" return:
" if POSITIONAL is 'none': returns the options as a dict
" if POSITIONAL is 'all' : returns the positional args as a list
" otherwise: returns [opts, positional]
function! argparse#parse(qargs, ...) abort
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
    let valid_keys = [valid_keys]
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
        if Type == '='
          let Type = get(default_modes, key, Type)
        endif
        call s:add_opt(valid_keys, opts, keymap, key, varpt, append, Type, var)
      elseif x =~ s:pat_short
        let [key, var] = matchlist(x, s:pat_short)[1:2]
        let types = get(default_modes, key, '')
        let append = '-'
        call s:add_opt(valid_keys, opts, keymap, key, var, append, types, var)
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
endfunction

" positional: [IFS] [keepempty]
function! argparse#split(str, ...)
  let IFS = get(a:000, 0, '')
  let IFS = IFS==''?get(g:, 'IFS', ''):IFS
  if IFS == ''
    if has('python3')
      py3 import vim, shlex
      py3 rv = shlex.split(vim.eval('a:str'))
      return py3eval('rv')
    else has('python')
      py3 import vim, shlex
      py3 rv = shlex.split(vim.eval('a:str'))
      return py3eval('rv')
    else

    endif
  else
    let keepempty = get(a:000, 1, 0)
    " only get one character
    let rv = split(a:str, printf('%s', IFS), keepempty)
    return rv
  endif
endfunction

function! s:valid(valid_keys, key)
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
endfunction
function! s:add_opt(valid_keys, opts, keymap, key, varpart, append, type, var)
  let key = get(a:keymap, a:key, a:key)
  let key = substitute(key, '-', '_', 'g')
  if !s:valid(a:valid_keys, key)
    throw printf('key %s is not acceptable', key)
  endif
  20Log key a:varpart a:append a:type a:var
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
    if tpnew == tpold && (tpnew == v:t_list || tpnew == v:t_string)
      call extend(a:opts[key], Var)
    else
      throw printf('parser: cannot extend type %s with type %s', tpold, tpnew)
    endif
  else
    throw 'parser: unexpected append type:' a:append
  endif
endfunction

function! argparse#call(funcname, ...)
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
endfunction

