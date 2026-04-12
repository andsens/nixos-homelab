{ ... }:
with builtins;
{
  jsonTrace = title: obj: trace ("${title}: ${toJSON obj}") obj;
}
