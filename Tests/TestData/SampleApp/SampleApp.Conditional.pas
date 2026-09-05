unit SampleApp.Conditional;

interface

uses
  // Declared() is not something we can evaluate without being the compiler, so both
  // branches have to survive and the edges have to say so.
  {$IF Declared(SomeSymbolWeCannotSee)}
  System.DateUtils,
  {$ELSE}
  System.Math,
  {$IFEND}
  System.SysUtils;

implementation

end.
