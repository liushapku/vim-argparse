function! argparse#utils#pop(dict, key, default)
  if has_key(a:dict, a:key)
    return remove(a:dict, a:key)
  else
    return a:default
  endif
endfunction

function! argparse#utils#add_range(count, line1, line2, ...)
  let rv = {
        \ '@count': a:count,
        \ '@line1': a:line1,
        \ '@line2': a:line2,
        \ }
  if a:0 > 0
    return extend(a:1, rv)
  else
    return rv
  endif
endfunction

" 4. to mimic :put, use  -range=-1 (<count>==-1? <line1>: <line2>), but
function! argparse#utils#smart_range(kwargs, ...)
  let opts = get(a:000, 0, {})
  let bufnr = get(opts, 'buf', bufnr('%'))
  let key = get(opts, 'key', 'range')
  let kwargs = a:kwargs
  let count = kwargs['@count']
  if has_key(kwargs, key)
    let range = kwargs[key]
    let rv = scripting#buffer#range(bufnr, range)
    let rv.count = rv.line2 - rv.line1 + 1
    let rv.user = 1
    return rv
  endif
  let user = count != -1
  let line1 = kwargs['@line1']
  let line2 = user? kwargs['@line2'] : line1
  let rv = {'line1': line1, 'line2': line2, 'count': count, 'user': user, 'buf': bufnr}
  if bufnr == bufnr('%')
  elseif user
    let rv.error = 'Not from the same buffer, cannot specify a command range, please use --range to specify a range'
  else
    let rv.error = 'Not from the same buffer, please use --range to specify a range'
  endif
  return rv
endfunction

"optional:
"prefix:
"default:
function! argparse#utils#smart_buf(kwargs, ...)
  let kwargs = a:kwargs
  let opts = get(a:000, 0, {})
  let prefix = get(opts, 'prefix', '')
  let default = get(opts, 'default', bufnr('%'))
  if has_key(kwargs, prefix . 'buf')
    let code = 'buf:' . string(kwargs[prefix.'buf'])
    let rv = bufnr(kwargs[prefix . 'buf'])
  elseif has_key(kwargs, prefix . 'win')
    let code = 'win:' . string(kwargs[prefix . 'win'])
    let rv = winbufnr(kwargs[prefix . 'win'])
  else
    let code = 'default:' . string(default)
    let rv = bufnr(default)
  endif
  if rv == -1
    Throw 'invalid buffer:' code
  else
    return rv
  endif
endfunction

