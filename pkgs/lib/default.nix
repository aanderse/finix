lib: prev:

rec {
  # Convert a command-line that uses lists for
  # execline blocks into the quoted block format.
  # This is what execlineb does before executing.
  quoteExecline = builtins.foldl' (acc: arg: acc ++ (
    if builtins.isList arg
    then map (_: " ${_}") (quoteExecline arg) ++ [ "" ]
    else [ arg ]
  )) [ ];

  escapeExeclineArg = arg:
    let string = toString arg; in
    if lib.match "[[:alnum:],._+:@%/-]+" string == null then
      ''"${lib.replaceString ''"'' ''\"'' string}"''
    else
     string;

  generators = prev.generators // {
    toPreserves = import ./generators/preserves.nix { inherit lib; };
  };
}
