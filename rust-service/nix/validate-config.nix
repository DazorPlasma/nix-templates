config: let
  inherit (builtins) isInt isString stringLength throw typeOf deepSeq;

  requireAttrs = path: value: expected: let
    actual = builtins.attrNames value;
    missing = builtins.filter (name: !(builtins.elem name actual)) expected;
    unexpected = builtins.filter (name: !(builtins.elem name expected)) actual;
  in
    if missing != []
    then throw "${path}: missing attribute(s): ${builtins.concatStringsSep ", " missing}"
    else if unexpected != []
    then throw "${path}: unexpected attribute(s): ${builtins.concatStringsSep ", " unexpected}"
    else value;

  requireString = path: value:
    if !(isString value) || stringLength value == 0
    then throw "${path}: expected a non-empty string, got ${typeOf value}"
    else value;

  requirePort = path: value:
    if !(isInt value) || value < 1 || value > 65535
    then throw "${path}: expected an integer port in 1..65535, got ${builtins.toString value}"
    else value;

  top = requireAttrs "config" config [
    "server"
    "logging"
  ];

  serverIn = requireAttrs "config.server" top.server ["apiPort"];
  loggingIn = requireAttrs "config.logging" top.logging ["filter"];

  result = {
    server = {
      apiPort = requirePort "config.server.apiPort" serverIn.apiPort;
    };

    logging = {
      filter = requireString "config.logging.filter" loggingIn.filter;
    };
  };
in
  deepSeq result result
