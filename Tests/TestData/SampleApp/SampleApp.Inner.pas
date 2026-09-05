unit SampleApp.Inner;

interface

uses
  {$IFDEF MSWINDOWS}
  Vcl.Graphics,
  {$ENDIF}
  System.Classes;

function Describe : string;

implementation

function Describe : string;
begin
  result := 'inner';
end;

end.
