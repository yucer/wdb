(function() {
  $(function() {
    var $code, $trace, code, file, fun, lno, _i, _len, _ref, _ref1, _results;
    $('#activate').click(function() {
      $.get('/__wdb/on').done(function() {
        return location.reload(true);
      });
      return false;
    });
    $('#title').text(_title).append($('<small>').text(_subtitle));
    if (trace.trace) {
      $('#wdb').append($trace = $('<article>', {
        "class": 'trace_500'
      }));
      _ref = trace.trace;
      _results = [];
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        _ref1 = _ref[_i], file = _ref1[0], lno = _ref1[1], fun = _ref1[2], code = _ref1[3];
        $trace.append($('<div>', {
          "class": 'traceline'
        }).append($('<div>', {
          "class": 'flno'
        }).text('File ' + file + ':' + lno), $('<div>', {
          "class": 'fun'
        }).text(fun), $code = $('<code>', {
          "class": 'cm'
        })));
        _results.push(CodeMirror.runMode(code || ' ', "python", $code.get(0)));
      }
      return _results;
    }
  });

}).call(this);

//# sourceMappingURL=500.js.map
