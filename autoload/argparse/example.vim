
function! s:append_cmd_undo_all()
  if !exists('s:changed')
    echomsg 'nothing to undo'
    return
  endif
  call scripting#buffer#execute2(s:changed, 'if getbufvar(%s, "changedtick") == %d | undo | endif')
  unlet s:changed
endfunction

function! s:append_cmd_undo(bufnr, changedtick)
endfunction

function! argparse#example#append(kwargs, args)
  try
    let kwargs = a:kwargs
    let args = a:args

    if get(kwargs, 'undo', 0)
      return s:append_cmd_undo_all()
    endif

    let cpos = getcurpos()
    let cline = line('.')
    let cbuf = bufnr('%')

    let keep_empty = get(kwargs, 'keep_empty', 0)
    if get(kwargs, 'replace', 0)
      let mode = 'replace'
    elseif get(kwargs, 'continue', 0)
      let mode = 'continue'
    else
      let mode = 'append'
    endif

    let to = argparse#utils#smart_buf(kwargs, {'prefix': 'to_'})
    let dest = get(kwargs, 'dest', '')
    let dest = scripting#buffer#range(to, dest)
    let to = dest.buf

    let lines = get(kwargs, 'data', [])
    if type(lines) == v:t_string
      let lines = split(lines, "\n", 1)
    endif

    let from = argparse#utils#smart_buf(kwargs, {'prefix': 'from_'})
    let range = argparse#utils#smart_range(kwargs, {'buf': from})
    if has_key(range, 'error')
      Throw range.error
    else
      let from = range.buf
      if range.user
        let data = scripting#buffer#getline(from, range.line1, range.line2)
        let delete_source = get(kwargs, 'delete', 0)
        call extend(lines, data)
      else
        let delete_source = 0
      endif
    endif

    if has_key(kwargs, 'register')
      for reg in split(kwargs.register, '\zs')
        let data = getreg(reg, 0, 1)
        call extend(lines, data)
      endfor
    endif
    let processed_args = 0
    if has_key(kwargs, 'command')
      if (kwargs.command == g:argparse#default ||
            \ kwargs.command == '' ) && len(args)
        let processed_args = 1
        let command = join(args, ' ')
      else
        let command = kwargs.command
      endif
      let data = split(execute(command), "\n", keep_empty)
      call extend(lines, data)
    endif
    if has_key(kwargs, 'system')
      if (kwargs.system == g:argparse#default ||
            \ kwargs.system == '' ) && len(args)
        let data = systemlist(args)
        let processed_args = 1
      else
        let data = systemlist(kwargs.system)
      endif
      call extend(lines, data)
    endif
    if !processed_args && len(args)
      call extend(lines, args)
    endif
    if has_key(kwargs, 'slice')
      let lines = eval(printf('lines[%s]', kwargs.slice))
    endif
    if has_key(kwargs, 'transform')
      call map(lines, {i,x-> scripting#function#apply(kwargs.transform, x)})
    elseif has_key(kwargs, 'Transform')
      let lines = scripting#function#apply(kwargs.Transform, lines)
    endif

    let deleted = 0
    let changed = []
    if delete_source && to == from
      " we need to delete source first if souce is after dest
      if range.line1 > dest.line2
        let deleted = 1
      elseif range.line2 < dest.line1
        "normal situation
      elseif mode == 'replace'
        " source is anyway to be deleted
        " do not need to delete anymore
        let deleted = -1
        if range.line2 > dest.line2
          let dest.line2 = range.line2
        endif
        if range.line1 < dest.line1
          let dest.line1 = range.line1
        endif
      elseif mode == 'append' && range.line2 >= dest.line2
        let dest.line2 = range.line1 - 1
        let deleted = 1
      elseif mode == 'continue' && range.line2 >= dest.line2
        " the line to continue is deleted, so work as append
        let mode = 'append'
        let dest.line2 = range.line1 - 1
        let deleted = 1
      else
        let msg = 'souce and dest mixed, do not know how to delete'
        if exists(':Throw')
          Throw msg
        else
          throw printf('(%s) %s in %s', msg, v:exception, v:throwpoint)
        endif
      endif
      if deleted == 1
        try
          call scripting#buffer#deletelines(from, range.line1, range.line2)
          call add(changed, [from, from, getbufvar(from, 'changedtick')])
        catch
          echomsg "delete source before append failed: " . v:exception
        endtry
      endif
    endif
    try
      if mode == 'append'
        call scripting#buffer#append(to, dest.line2, lines)
      elseif mode == 'continue'
        call scripting#buffer#continuelines(to, dest.line2, lines)
      elseif mode == 'replace'
        call scripting#buffer#setlines(to, dest.line1, dest.line2, lines)
      endif
      call add(changed, [to, to, getbufvar(to, 'changedtick')])
    catch
      let msg = printf("append to buffer %s failed", to)
      if exists(':Throw')
        Throw msg
      else
        throw printf('(%s) %s in %s', msg, v:exception, v:throwpoint)
      endif
    endtry
    if delete_source && deleted == 0
      try
        call scripting#buffer#deletelines(from, range.line1, range.line2)
        call add(changed, [from, from, getbufvar(from, 'changedtick')])
      catch
        echomsg "delete source failed"
      endtry
    endif
    let s:changed = uniq(changed)
    let g:changed = s:changed
  catch
    if exists(':Throw')
      Throw
    else
      throw printf('%s in %s', v:exception, v:throwpoint)
    endif
  endtry
endfunction


let s:meta = {
      \ '[KMAP]': {'R':'replace', 'C':'continue', 'D': 'delete',
      \     'to': 'to_win', 'from': 'from_win', 'reg': 'register',
      \     'f': 'from_win', 'F' : 'from_buf', 't': 'to_win', 'T': 'to_buf',
      \     'r': 'range',  'd': 'dest',
      \     },
      \ '[POSITIONAL]': 'auto',
      \ }
function! s:default(count, line1, line2, bang)
  let opts = argparse#utils#add_range(a:count, a:line1, a:line2)
  if a:bang
    let opts.system = ''
  endif
  return opts
endfunction
function! argparse#example#append_cmd(qargs, count, line1, line2, bang)
  let default = s:default(a:count, a:line1, a:line2, a:bang)
  let [options, positional] = argparse#parse(a:qargs, s:meta, default)
  call argparse#example#append(options, positional)
endfunction
