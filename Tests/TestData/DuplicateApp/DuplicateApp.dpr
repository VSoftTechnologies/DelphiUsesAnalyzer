program DuplicateApp;

{
  Two units in two folders, each folder with its own copy of DuplicateApp.Shared. A unit's
  own folder is searched before the search paths, so First and Second each find a
  different copy - and the graph has room for only one.
}

{$APPTYPE CONSOLE}

uses
  DuplicateApp.First in 'First\DuplicateApp.First.pas',
  DuplicateApp.Second in 'Second\DuplicateApp.Second.pas',
  DuplicateApp.SecondToo in 'Second\DuplicateApp.SecondToo.pas';

begin
end.
