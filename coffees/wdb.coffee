# This file is part of wdb
#
# wdb Copyright (C) 2012  Florian Mounier, Kozea
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

#*** Initializations ***#
debug = true

class Log
  log: ->
    if debug
      name = "[#{@constructor.name}]"
      log_args = [name].concat Array.prototype.slice.call(arguments, 0)
      console.log.apply console, log_args

  fail: ->
    name = @constructor.name
    log_args = [name].concat Array.prototype.slice.call(arguments, 0)
    console.error.apply console, log_args

class WS extends Log
  constructor: (@wdb) ->
    # Open a websocket in case of request break
    @url = "ws://#{document.location.host}/websocket/#{_uuid}"
    @log 'Opening new socket', @url
    @ws = new WebSocket @url
    @ws.onclose = @close.bind(@)
    @ws.onopen = @open.bind(@)
    @ws.onerror = @error.bind(@)
    @ws.onmessage = @message.bind(@)

  time: ->
    date = new Date()
    "#{date.getHours()}:#{date.getMinutes()}:" +
    "#{date.getSeconds()}.#{date.getMilliseconds()}"

  close: (m) ->
    @log "Closed", m

  error: (m) ->
    @fail "Error", m

  open: (m) ->
    # We are connected, ie: in request break
    @log "Open", m
    @wdb.opening()

  message: (m) ->
    # Open a websocket in case of request break
    message = m.data
    pipe = message.indexOf('|')
    if pipe > -1
      cmd = message.substr(0, pipe)
      data = JSON.parse message.substr(pipe + 1)
    else
      cmd = message
    @log @time(), '<-', cmd
    cmd = cmd.toLowerCase()
    if cmd of @wdb
      @wdb[cmd.toLowerCase()] data
    else
      @fail 'Unknown command', cmd

  send: (cmd, data=null) ->
    if data
      msg = "#{cmd}|#{data}"
    else
      msg = cmd
    @log @time(), '->', msg
    @ws.send msg

class Codemirror extends Log
  constructor: (@wdb) ->
    CodeMirror.keyMap.wdb =
      Esc: (cm) => @toggle_edition false
      fallthrough: ["default"]

    CodeMirror.commands.save = =>
      @wdb.ws.send 'Save', "#{@cm._fn}|#{@cm.getValue()}"

    @cm = null

  new: (file, name, rw=false) ->
    @cm = CodeMirror ((elt) ->
      $('#source-editor').prepend(elt)
      $(elt).addClass(if rw then 'rw' else 'ro').addClass('cm')
      ) , (
      value: file,
      mode:  @get_mode(name),
      readOnly: !rw,
      theme: 'wdb',
      keyMap: 'wdb',
      gutters: ["breakpoints", "CodeMirror-linenumbers"],
      lineNumbers: true)
    @cm._bg_marks = cls: {}, marks: {}
    @cm._rw = rw
    @cm._fn = name
    @cm._file = file
    @cm._fun = null
    @cm._last_hl = null

    @cm.on("gutterClick", (@cm, n) =>
      @wdb.toggle_break ':' + (n + 1)
    )

    @cm.addClass = (lno, cls) =>
      @cm.addLineClass(lno - 1, 'background', cls)
      if @cm._bg_marks.cls[lno]
        @cm._bg_marks.cls[lno] = @cm._bg_marks.cls[lno] + ' ' + cls
      else
        @cm._bg_marks.cls[lno] = cls

    @cm.removeClass = (lno, cls) =>
      @cm.removeLineClass(lno - 1, 'background', cls)
      delete @cm._bg_marks.cls[lno]

    @cm.addMark = (lno, cls, char) =>
      @cm._bg_marks.marks[lno] = [cls, char]
      @cm.setGutterMarker(lno - 1, "breakpoints",
        $('<div>', class: cls).html(char).get(0))

    @cm.removeMark = (lno) =>
      delete @cm._bg_marks.marks[lno]
      @cm.setGutterMarker(lno - 1, "breakpoints", null)

  toggle_edition: (rw) ->
    cls = $.extend({}, @cm._bg_marks.cls)
    marks = $.extend({}, @cm._bg_marks.marks)
    scroll = $('#source .CodeMirror-scroll').scrollTop()
    $('#source .CodeMirror').remove()
    @cm = @new @cm._file, @cm._fn, rw
    for lno of cls
      @cm.addClass(lno, cls[lno])
    for lno of marks
      [cls, char] = marks[lno]
      @cm.addMark(lno, cls, char)
    $('#source .CodeMirror-scroll').scrollTop(scroll)
    @print
      for: "Toggling edition"
      result: "Edit mode #{if rw then 'on' else 'off'}"

  select: (data, frame) ->
    if not @cm
      @new data.file, data.name
      @wdb.$eval.focus()
    else
      if @cm._fn == data.name
        if @cm._fun != frame.function
          for lno of @cm._bg_marks.cls
            @cm.removeLineClass(lno - 1, 'background')

        for lno of @cm._bg_marks.marks
          @cm.setGutterMarker(lno - 1, 'breakpoints', null)
        if @cm._last_hl
          @cm.removeLineClass(lno - 1, 'background')
          @cm.addLineClass(lno - 1, 'background', 'footstep')
      else
        @cm.setValue data.file
        @cm._fn = data.name
        @cm._fun = frame.function
        @cm._file = data.file
        @cm._last_hl = null
      @cm._bg_marks.cls = {}
      @cm._bg_marks.marks = {}

    for lno in data.breaks
      @cm.addClass(lno, 'breakpoint')
      @cm.addMark(lno, 'breakpoint', '●')

    @cm.addClass(frame.lno, 'highlighted')
    @cm.addMark(frame.lno, 'highlighted', '➤')
    if @cm._fun != frame.function and
       frame.function != '<module>'
      for lno in [frame.flno...frame.llno + 1]
        @cm.addClass(lno, 'ctx')
        if lno == frame.flno
          @cm.addClass(lno, 'ctx-top')
        else if lno == frame.llno
          @cm.addClass(lno, 'ctx-bottom')
      @cm._fun = frame.function
    @cm._last_hl = frame.lno

    @cm.scrollIntoView(line: frame.lno, ch: 1, 1)
    $scroll = $ '#source .CodeMirror-scroll'
    $hline = $ '#source .highlighted'
    $scroll.scrollTop(
      $hline.offset().top - $scroll.offset().top +
      $scroll.scrollTop() - $scroll.height() / 2)

  get_mode: (fn) ->
    ext = fn.split('.').splice(-1)[0]
    if ext == 'py'
      'python'
    else if ext == 'jinja2'
      'jinja2'
    'python'


class Wdb extends Log
  constructor: ->
    @started = false
    @to_complete = null
    @ws = new WS(@)
    @cm = new Codemirror(@)
    @cwd = null
    @backsearch = null
    @cmd_hist = []
    @session_cmd_hist = {}
    @file_cache = {}
    @last_cmd = null

    @waited_for_ws = 0
    @$state = $('.state')
    @$waiter = $('#waiter')
    @$wdb = $('#wdb')
    @$eval = $('#eval')
    @$source = $('#source')
    @$traceback = $('#traceback')
    @$traceback.on 'click', '.traceline', @select_click.bind(@)
    @$title = $('#title')
    try
      @cmd_hist = JSON.parse(localStorage['cmd_hist'])
    catch e
      @fail e

  opening: ->
    # Start by getting current trace
    if not @started
      @register_handlers()
      @started = true
    @start()

    @$waiter.remove()
    @$wdb.show()
    @$eval.autosize()

  working: ->
    @$state.addClass('on')

  chilling: ->
    @$state.removeClass('on')

  start: ->
    @ws.send 'Start'

  init: (data) ->
    @cwd = data.cwd

  title: (data) ->
    @$title
      .text(data.title)
      .attr('title', data.title)
      .append(
        $('<small>')
          .text(data.subtitle)
          .attr('title', data.subtitle))

  trace: (data) ->
    @$traceback.empty()
    for frame in data.trace
      $traceline = $('<div>')
        .addClass('traceline')
        .attr('id', 'trace-' + frame.level)
        .attr('data-level', frame.level)
      if frame.current
        $traceline.addClass('real-selected')
      $tracefile = $('<span>').addClass('tracefile').text(frame.file)
      $tracelno = $('<span>').addClass('tracelno').text(frame.lno)
      $tracefun = $('<span>').addClass('tracefun').text(frame.function)

      $tracefilelno = $('<div>')
        .addClass('tracefilelno')
        .append($tracefile)
        .append($tracelno)

      $tracefunfun = $('<div>')
        .addClass('tracefunfun')
        .append($tracefun)

      if frame.file.indexOf('site-packages') > 0
        suffix = frame.file.split('site-packages').slice(-1)[0]
        $tracefile.text(suffix)
        $tracefile.prepend(
          $('<span>')
            .addClass('tracestar')
            .text('*')
            .attr(title: frame.file))

      if frame.file.indexOf(@cwd) == 0
        suffix = frame.file.split(@cwd).slice(-1)[0]
        $tracefile.text(suffix)
        $tracefile.prepend(
          $('<span>')
            .addClass('tracestar')
            .text('.')
            .attr(title: frame.file))

      $tracecode = $('<div>').addClass('tracecode')

      @code $tracecode, frame.code
      $traceline.append $tracefilelno
      $traceline.append $tracecode
      $traceline.append $tracefunfun
      @$traceback.prepend $traceline

  select_click: (e) ->
    @ws.send 'Select', $(e.currentTarget).attr('data-level')

  selectcheck: (data) ->
    if data.name not of @file_cache
      @ws.send 'File', data.name
    else
      data.file = @file_cache[data.name]
      @select data

  select: (data) ->
    @$source = $ '#source'
    current_frame = data.frame
    $('#interpreter').show()
    $('.traceline').removeClass('selected')
    $('#trace-' + current_frame.level).addClass('selected')
    @$eval.val('').attr('data-index', -1).trigger('autosize.resize')
    @file_cache[data.name] = data.file
    @cm.select(data, current_frame)
    @chilling()

  ellipsize: ($code) ->
    $code.find('span.cm-string').each ->
      txt = $(@).text()
      if txt.length > 128
        $(@).text ''
        $(@).append $('<span class="short close">').text(txt.substr(0, 128))
        $(@).append $('<span class="long">').text(txt.substr(128))

  code: (parent, src, classes=[], html=false) ->
    if html
      if src[0] != '<' or src.slice(-1) != '>'
        $node = $('<div>', class: 'out').html(src)
      else
        $node = $(src)
      parent.append $node
      $node.add($node.find('*')).contents().filter(->
        @nodeType == 3 and @nodeValue.length > 0 and
        not $(@parentElement).closest('thead').size()
      )
      .wrap('<code>')
      .parent()
      .each (i, elt) =>
        $code = $(elt)
        $code.addClass('waiting_for_hl').addClass('cm')
        for cls in classes
          $code.addClass(cls)
        setTimeout (=>
          CodeMirror.runMode $code.text(), "python", $code.get(0)
          $code.removeClass('waiting_for_hl')
          @ellipsize $code
        ), 50
    else
      $code = $('<code>', 'class': 'cm')
      for cls in classes
        $code.addClass(cls)
      parent.append $code
      CodeMirror.runMode src, "python", $code.get(0)
      @ellipsize $code

    $code

  historize: (snippet) ->
    filename = $('.selected .tracefile').text()
    if not (filename of @session_cmd_hist)
      @session_cmd_hist[filename] = []

    while (index = @cmd_hist.indexOf(snippet)) != -1
      @cmd_hist.splice(index, 1)

    @cmd_hist.unshift snippet
    @session_cmd_hist[filename].unshift snippet

    localStorage and localStorage['cmd_hist'] = JSON.stringify @cmd_hist

  execute: (snippet) ->
    snippet = snippet.trim()
    @historize snippet

    cmd = =>
      @ws.send.apply @ws, arguments
      last_cmd = arguments

    if snippet.indexOf('.') == 0
      space = snippet.indexOf(' ')
      if space > -1
        key = snippet.substr(1, space - 1)
        data = snippet.substr(space + 1)
      else
        key = snippet.substr(1)
        data = ''
      switch key
        when 'b' then @toggle_break data
        when 'c' then cmd 'Continue'
        when 'd' then cmd 'Dump', data
        when 'e' then @cm.toggle_edition(not @cm.cm._rw)
        when 'g' then @cls()
        when 'h' then @print_help()
        when 'j' then cmd 'Jump', data
        when 'l' then cmd 'Breakpoints'
        when 'n' then cmd 'Next'
        when 'q' then cmd 'Quit'
        when 'r' then cmd 'Return'
        when 's' then cmd 'Step'
        when 'i' then cmd 'Display', data
        when 't' then @toggle_break data, true
        when 'u' then cmd 'Until'
        when 'w' then cmd 'Watch', data
        when 'z' then cmd 'Unbreak', data
        when 'f' then @print_hist @session_cmd_hist[$('.selected .tracefile')
          .text()]
      return

    else if snippet.indexOf('?') == 0
      cmd 'Dump', snippet.slice(1).trim()
      @working()
      @suggest_stop()
      return
    else if snippet is '' and last_cmd
      cmd.apply @, last_cmd
      return
    if snippet
      @ws.send 'Eval', snippet
      @$eval.val(@$eval.val() + '…')
        .trigger('autosize.resize')
        .prop('disabled', true)
      @working()

  cls: ->
    $('#completions').height(
      $('#interpreter').height() - $('#prompt').innerHeight())
    @termscroll()
    @$eval.val('').trigger('autosize.resize')

  print_hist: (hist) ->
    @print
      for: 'History'
      result: hist
        .slice(0)
        .reverse()
        .filter((e) -> e.indexOf('.') != 0)
        .join('\n')

  print_help: ->
    @print for: 'Supported commands', result: '''
.s or [Ctrl] + [↓] or [F11]    : \
 Step into
.n or [Ctrl] + [→] or [F10]    : \
 Step over (Next)
.r or [Ctrl] + [↑] or [F9]     : \
 Step out (Return)
.c or [Ctrl] + [←] or [F8]     : \
 Continue
.u or [F7]                     : \
 Until (Next over loops)
.j lineno                      : \
 Jump to lineno (Must be at bottom frame and in the same function)
.b arg                         : \
 Set a session breakpoint  see below for what arg can be*
.t arg                         : \
 Set a temporary breakpoint, arg follow the same syntax as .b
.z arg                         : \
 Delete existing breakpoint
.l                             : \
 List active breakpoints
.f                             : \
 Echo all typed commands in the current debugging session
.d expression                  : \
 Dump the result of expression in a table
.w expression                  : \
 Watch expression in curent file (Click on the name to remove)
.q                             : \
 Quit
.h                             : \
 Get some help
.e                             : \
 Toggle file edition mode
.g                             : \
 Clear prompt
.i [mime/type;]expression      : \
 Display the result in an embed, mime type defaults to "text/html"
iterable!sthg                  : \
 If cutter is installed, executes cut(iterable).sthg
expr >! file                   : \
 Write the result of expr in file
!< file                        : \
 Eval the content of file
[Enter]                        : \
 Eval the current selected text in page, useful to eval code in the source

* arg is using the following syntax:
    [file/module][:lineno][#function][,condition]
which means:
    - [file]                    : \
 Break if any line of `file` is executed
    - [file]:lineno             : \
 Break on `file` at `lineno`
    - [file][:lineno],condition : \
 Break on `file` at `lineno` if `condition` is True (ie: i == 10)
    - [file]#function           : \
 Break when inside `function` function
File is always current file by default and you can also \
specify a module like `logging.config`.
'''

  termscroll: ->
    $('#interpreter')
      .stop(true)
      .animate((scrollTop: $('#scrollback').height()), 1000)

  print: (data) ->
    @suggest_stop()
    snippet = @$eval.val()
    @code($('#scrollback'), data.for, ['prompted'])
    @code($('#scrollback'), data.result, [], true)
    @$eval
      .val('')
      .prop('disabled', false)
      .attr('data-index', -1)
      .trigger('autosize.resize')
      .focus()
    $('#completions').attr('style', '')
    @termscroll()
    @chilling()

  echo: (data) ->
    @code($('#scrollback'), data.for, ['prompted'])
    @code($('#scrollback'), data.val or '', [], true)
    @termscroll()
    @chilling()

  dump: (data) ->
    @code($('#scrollback'), data.for, ['prompted'])
    $container = $('<div>')
    $table = $('<table>', class: 'object').appendTo($container)
    $table.append(
      $('<thead>', class: 'toggle hidden').append(
        $('<tr>')
          .append($('<td>', class: 'core', colspan: 2)
          .text('Core Members'))))
    $core_tbody = $('<tbody>', class: 'core hidden').appendTo($table)

    $table.append(
      $('<thead>', class: 'toggle hidden').append(
        $('<tr>')
          .append($('<td>', class: 'method', colspan: 2)
          .text('Methods'))))
    $method_tbody = $('<tbody>', class: 'method hidden').appendTo($table)

    $table.append(
      $('<thead>', class: 'toggle shown').append(
        $('<tr>').append(
          $('<td>', class: 'attr', colspan: 2)
            .text('Attributes'))))
    $attr_tbody = $('<tbody>', class: 'attr shown').appendTo($table)

    for key, val of data.val
      $tbody = $attr_tbody
      if key.indexOf('__') == 0 and key.indexOf('__', key.length - 2) != -1
        $tbody = $core_tbody
      else if val.type.indexOf('method') != -1
        $tbody = $method_tbody

      $tbody.append($('<tr>')
        .append($('<td>').text(key))
        .append($('<td>').html(val.val)))
    @code($('#scrollback'), $container.html(), [], true)
    @termscroll()
    @$eval.val('')
      .prop('disabled', false)
      .trigger('autosize.resize')
      .focus()
    @chilling()

  breakset: (data) ->
    if data.lno
      @cm.cm.removeClass(data.lno, 'ask-breakpoint')
      @cm.cm.addClass(data.lno, 'breakpoint')
      @cm.cm.addMark(data.lno, 'breakpoint',
        if data.temporary then '○' else '●')

      if data.cond
        $line.attr('title', "On [#{data.cond}]")
    if @$eval.val().indexOf('.b ') == 0 or @$eval.val().indexOf('.t ') == 0
      @$eval.val('').prop('disabled', false).trigger('autosize.resize').focus()
    @chilling()

  breakunset: (data) ->
    @cm.cm.removeClass(data.lno, 'ask-breakpoint')
    if @$eval.val().indexOf('.b ') == 0
      @$eval.val('').prop('disabled', false).trigger('autosize.resize').focus()
    @chilling()

  toggle_break: (arg, temporary) ->
    cmd = if temporary then 'TBreak' else 'Break'
    lno = NaN
    if arg.indexOf(':') > -1
      lno = arg.split(':')[1]
      if lno.indexOf(',') > -1
        lno = arg.split(',')[0]
      if lno.indexOf('#') > -1
        lno = arg.split('#')[0]
      lno = parseInt(lno)

    if isNaN lno
      # If lno is not a number
      # Can't set line info here, returning
      @ws.send cmd, arg
      return

    cls = @cm.cm.lineInfo(lno - 1).bgClass or ''
    if cls.split(' ').indexOf('breakpoint') > -1
      @cm.cm.removeMark(lno)
      @cm.cm.removeClass(lno, 'breakpoint')
      @cm.cm.addClass(lno, 'ask-breakpoint')
      @ws.send 'Unbreak', ":#{lno}"
    else
      @cm.cm.addClass(lno, 'ask-breakpoint')
      @ws.send cmd, arg

  format_fun: (p) ->
    tags = [
      $('<span>', class: 'fun_name', title: p.module).text(p.call_name),
      $('<span>', class: 'fun_punct').text('(')]
    for param, i in p.params
      cls = 'fun_param'
      if i == p.index or (i == p.params.length - 1 and p.index > i)
        cls = 'fun_param active'
      tags.push $('<span>', class: cls).text(param)
      if i != p.params.length - 1
        tags.push $('<span>', class: 'fun_punct').text(', ')

    tags.push $('<span>', class: 'fun_punct').text(')')
    tags

  suggest: (data) ->
    if data
      $comp_wrapper = $('#completions')
      $comp = $('#completions table').empty()
      $comp.append($('<thead><tr><th id="comp-desc" colspan="5">'))
      height = $comp_wrapper.height()
      added = []
      for param in data.params
        $('#comp-desc').append(format_fun(param))

      if data.completions.length
        $tbody = $('<tbody>')
        base_len = data.completions[0].base.length
        @$eval.data
          root: @$eval.val().substr(0, @$eval.val().length - base_len)
      for completion, index in data.completions
        if (completion.base + completion.complete) in added
          continue
        added.push(completion.base + completion.complete)
        if index % 5 == 0
          $tbody.append($appender = $('<tr>'))

        $appender.append($td = $('<td>').attr('title', completion.description)
          .append($('<span>').addClass('base').text(completion.base))
          .append($('<span>').addClass('completion').text(completion.complete)))
        if not completion.complete
          $td.addClass('active complete')
          $('#comp-desc').html($td.attr('title'))
      $comp.append($tbody)
      $comp_wrapper.height(Math.max(height, $comp.height()))
      @termscroll()
    if @to_complete
      @ws.send 'Complete', @to_complete
      @to_complete = false
    else
      @to_complete = null

  suggest_stop: ->
    $('#completions table').empty()

  watched: (data) ->
    $watchers = $('#watchers')
    for own watcher, value of data
      $watcher = $watchers
        .find(".watching")
        .filter((e) -> $(e).attr('data-expr') == watcher)
      if not $watcher.size()
        $name = $('<code>', class: "name")
        $value = $('<div>', class: "value")
        $watchers.append(
          $watcher = $('<div>', class: "watching")
            .attr('data-expr', watcher)
            .append($name.text(watcher), $('<code>').text(': '), $value))
        @code($value, value.toString(), [], true)
      else
        $watcher.find('.value code').remove()
        @code($watcher.find('.value'), value.toString(), [], true)
      $watcher.addClass('updated')
    $watchers.find('.watching:not(.updated)').remove()
    $watchers.find('.watching').removeClass('updated')


  ack: ->
    @$eval.val('').trigger('autosize.resize')

  display: (data) ->
    @suggest_stop()
    snippet = @$eval.val()
    @code($('#scrollback'), data.for, ['prompted'])
    if data.type.indexOf('image') >= 0
      $tag = $("<img>")
    else if data.type.indexOf('audio') >= 0
      $tag = $("<audio>", controls: 'controls', autoplay: 'autoplay')
    else if data.type.indexOf('video') >= 0 or data.type.indexOf('/ogg') >= 0
      $tag = $("<video>", controls: 'controls', autoplay: 'autoplay')
    else
      $tag = $("<iframe>")

    $tag.addClass('display')
    $tag.attr('src', "data:#{data.type};charset=UTF-8;base64,#{data.val}")
    $('#scrollback').append($tag)
    @$eval
      .val('')
      .prop('disabled', false)
      .attr('data-index', -1)
      .trigger('autosize.resize')
      .focus()
    $('#completions').attr('style', '')
    @termscroll()
    @chilling()

  searchback: ->
    @suggest_stop()
    index = @backsearch
    val = @$eval.val()
    for h in @cmd_hist
      re = new RegExp('(' + val + ')', 'gi')
      if re.test(h)
        index--
        if index == 0
          $('#backsearch')
            .html(h.replace(re, '<span class="backsearched">$1</span>'))
          return
    if @backsearch == 1
      @searchback_stop()
      return
    @backsearch = Math.max(@backsearch - 1, 1)

  searchback_stop: (validate) ->
    if validate
      @$eval.val($('#backsearch').text()).trigger('autosize.resize')
    $('#backsearch').html('')
    @backsearch = null

  die: ->
    $('#source,#traceback').remove()
    $('h1').html('Dead<small>Program has exited</small>')
    @ws.ws.close()
    setTimeout (-> window.close()), 10

  register_handlers: ->
    $('body,html').on 'keydown', (e) =>
      if @cm.cm?._rw
        return true
      if (e.ctrlKey and e.keyCode == 37) or e.keyCode == 119
        # ctrl + left  or F8
        @ws.send 'Continue'
      else if (e.ctrlKey and e.keyCode == 38) or e.keyCode == 120
        # ctrl + up  or F9
        @ws.send 'Return'
      else if (e.ctrlKey and e.keyCode == 39) or e.keyCode == 121
        # ctrl + right or F10
        @ws.send 'Next'
      else if (e.ctrlKey and e.keyCode == 40) or e.keyCode == 122
        # ctrl + down  or F11
        @ws.send 'Step'
      else if e.keyCode == 118 # F7
        @ws.send 'Until'
      else
        return true
      @working()
      false

    @$eval.on 'keydown', (e) =>
      if e.altKey and e.keyCode == 82 and @backsearch # R
        @backsearch = Math.max(@backsearch - 1, 1)
        @searchback()
        return false

      if e.ctrlKey
        if e.keyCode == 82 # R
          if @backsearch is null
            @backsearch = 1
          else
            if e.shiftKey
              @backsearch = Math.max(@backsearch - 1, 1)
            else
              @backsearch++
          @searchback()
          return false
        else if e.keyCode == 67 # C
          @searchback_stop()
        else if e.keyCode == 68 # D
          @ws.send 'Quit'
        else
          e.stopPropagation()
          return

      if e.keyCode == 13 # Enter
        if @backsearch
          @searchback_stop true
          return false
        if $('#completions table td.active').length and
           not $('#completions table td.complete').length
          @suggest_stop()
          return false
        if not e.shiftKey
          @execute @$eval.val()
          return false

      else if e.keyCode == 27 # Escape
        @suggest_stop()
        @searchback_stop()
        return false

      else if e.keyCode == 9 # Tab
        if e.shiftKey
          txtarea = @$eval.get(0)
          startPos = txtarea.selectionStart
          endPos = txtarea.selectionEnd
          if startPos or startPos == '0'
            @$eval.val(
              @$eval.val().substring(0, startPos) +
              '  ' +
              @$eval.val().substring(endPos, @$eval.val().length)
            ).trigger('autosize.resize')
          else
            @$eval.val(@$eval.val() + '  ').trigger('autosize.resize')
          return false
        if @backsearch
          return false
        $tds = $('#completions table td')
        $active = $tds.filter('.active')
        if $tds.length
          if not $active.length
            $active = $tds.first().addClass('active')
          else
            index = $tds.index($active)
            if index is $tds.length - 1
              index = 0
            else
              index++
            $active.removeClass('active complete')
            $active = $tds.eq(index).addClass('active')
          base = $active.find('.base').text()
          completion = $active.find('.completion').text()
          @$eval
            .val($eval.data().root + base + completion)
            .trigger('autosize.resize')
          $('#comp-desc').text($active.attr('title'))
          @termscroll()
        return false

      else if e.keyCode == 38  # Up
        filename = $('.selected .tracefile').text()
        if not e.shiftKey
          index = parseInt(@$eval.attr('data-index')) + 1
          if index >= 0 and index < @cmd_hist.length
            to_set = @cmd_hist[index]
            if index == 0
              @$eval.attr('data-current', @$eval.val())
            @$eval.val(to_set)
              .attr('data-index', index).trigger('autosize.resize')
            @suggest_stop()
            @termscroll()
            return false

      else if e.keyCode == 40  # Down
        filename = $('.selected .tracefile').text()
        if not e.shiftKey
          index = parseInt($eval.attr('data-index')) - 1
          if index >= -1 and index < @cmd_hist.length
            if index == -1
              to_set = @$eval.attr('data-current')
            else
              to_set = @cmd_hist[index]
            @$eval.val(to_set)
              .attr('data-index', index).trigger('autosize.resize')
            @suggest_stop()
            @termscroll()
            return false

    $("#scrollback, #watchers").on('click', 'a.inspect', (e) =>
      @ws.send 'Inspect', $(e.currentTarget).attr('href')
      @working()
      false
    ).on('click', '.short.close', ->
      $(@).addClass('open').removeClass('close').next('.long').show('fast')
    ).on('click', '.long,.short.open', ->
      elt = if $(@).hasClass('long') then $(@) else $(@).next('.long')
      elt.hide('fast').prev('.short').removeClass('open').addClass('close')
    ).on('click', '.toggle', ->
      $(@).add($(@).next()).toggleClass('hidden', 'shown')
    )

    $("#watchers").on('click', '.watching .name', (e) =>
      @ws.send 'Unwatch', $(e.currentTarget)
        .closest('.watching')
        .attr('data-expr')
      @working()
    )

    $("#source").on('mouseup', 'span', (e) =>
      if e.which == 2 # Middle
        target = $(e.currentTarget).text().trim()
        @historize target
        @ws.send 'Dump', target
        @working()
    )

    $(document).on('keydown', (e) =>
      if e.keyCode == 13
        sel = @cm.cm.getSelection().trim()
        if sel
          @historize sel
          @ws.send 'Eval', sel
          false
    )

    @$eval.on('input', (e) =>
      txt = $(e.currentTarget).val()
      if @backsearch
        if not txt
          @searchback_stop()
        else
          @backsearch = 1
          @searchback()
        return
      hist = @session_cmd_hist[$('.selected .tracefile').text()] or []
      if txt and txt[0] != '.'
        comp = hist
          .slice(0)
          .reverse()
          .filter((e) -> e.indexOf('.') != 0)
          .join('\n') + '\n' + txt

        if @to_complete == null
          @ws.send 'Complete', comp
          @to_complete = false
        else
          @to_complete = comp
      else
        @suggest_stop()
    ).on('blur', =>
      @searchback_stop()
    )

$ =>
  setTimeout(->
    $('#deactivate').click () ->
      window.wdb.ws.send('Disable')
      false
  , 250)
  @wdb = new Wdb()
