program SampleApp;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  SampleApp.Middle in 'SampleApp.Middle.pas',
  SampleApp.Conditional in 'SampleApp.Conditional.pas';

begin
  Writeln(SampleApp.Middle.Describe);
end.
