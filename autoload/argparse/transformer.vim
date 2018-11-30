let s:_ = {}
function! argparse#transformer#_set_eval_context(dict)
  let s:_ = a:dict
endfunction

function! s:eval(str)  " change context
  let __ = argparse#_get_context()
  let _ = argparse#_current_opts()
  try
    return eval(a:str)
  catch
    Throw a:str
  endtry
endfunction

function! argparse#transformer#eval(str)
  return s:eval(a:str)
endfunction


let s:function_pattern = printf('\v([a-zA-Z_][a-zA-Z0-9_#:]*)(([%s])(.*))?', g:argparse#delimiters)
function! s:func(str)
  if a:str =~ '^\s*{.\+->.\+}\s*$'
    return eval(a:str)
  endif
  let rv = scripting#matchlist(a:str, s:function_pattern)
  let [funname, var, delim, params] = rv[1:4]
  if var == ''
    return function(funname)
  else
    let params = split(params, '\V'. delim)
    return function(funname, params)
  endif
endfunction
function! argparse#transformer#func(str)
  return s:func(a:str)
endfunction
function! argparse#transformer#call(str)
  return s:func(a:str)()
endfunction


function! argparse#transformer#list_eval(str)
  return map(split(a:str, ','), 's:eval(v:val)')
endfunction

function! s:dict(str, type)
  let items = split(a:str, ',')
  let rv = {}
  for item in items
    let matched = scripting#matchlist(item, '\v([^:]+):(.*)')
    if empty(matched)
      throw 'parser:' item 'does not match dict item'
    else
      let [key, Val] = matched[1:2]
      if a:type == 'eval'
        let Val = s:eval(Val)
      elseif a:type == 'func'
        let Val = s:func(Val)
      endif
      let rv[key] = Val
    endif
  endfor
  return rv
endfunction
function! argparse#transformer#dict(str)
  return s:dict(a:str, '')
endfunction
function! argparse#transformer#dict_eval(str)
  return s:dict(a:str, 'eval')
endfunction
function! argparse#transformer#dict_func(str)
  return s:dict(a:str, 'func')
endfunction
