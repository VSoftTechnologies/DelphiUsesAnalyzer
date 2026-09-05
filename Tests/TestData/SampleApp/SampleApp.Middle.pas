unit SampleApp.Middle;

// The only route from the program to anything in the vcl runs through this unit and
// then SampleApp.Inner, which is what the end to end test asserts on.

interface

function Describe : string;

implementation

uses
  SampleApp.Inner;

function Describe : string;
begin
  result := SampleApp.Inner.Describe;
end;

end.
