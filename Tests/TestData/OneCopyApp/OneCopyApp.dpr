program OneCopyApp;

{
  One copy of OneCopyApp.B, reached two ways: through a search path that spells its folder
  with a .. in it, and then from A's own folder. That is one file, not two copies.
}

{$APPTYPE CONSOLE}

uses
  OneCopyApp.B,
  OneCopyApp.A in 'Lib\OneCopyApp.A.pas';

begin
end.
