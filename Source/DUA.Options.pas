unit DUA.Options;

interface

uses
  DUA.Analyzer,
  DUA.Rules;

type
  TAnalyzerCommand = (acAnalyze, acWhy, acReferences, acCheck, acCost, acDeps,
                      acPath, acCycles, acDiff, acHelp);

  /// <summary>
  ///   The command line, collected into one place. VSoft.CommandLine calls an anonymous
  ///   method per option, so the values have to land on class vars.
  /// </summary>
  TCommandLineOptions = class
  public
    class var CommandName : string;
    class var ProjectFile : string;
    /// <summary>The unit or glob that why, references, cost and deps ask about.</summary>
    class var TargetUnit : string;
    /// <summary>Where path starts from. The unit it is heading for is TargetUnit.</summary>
    class var FromUnit : string;
    /// <summary>The right hand side of a diff - another project or another saved graph.</summary>
    class var OtherFile : string;
    class var HelpCommand : string;
    class var Config : string;
    class var Platform : string;
    class var Compiler : string;
    class var OutputFile : string;
    class var Deep : boolean;
    class var Quiet : boolean;
    class var MaxPaths : integer;
    class var Limit : integer;
    /// <summary>How far down the deps tree to go. 0 means all of it.</summary>
    class var Depth : integer;
    class var DefinesText : string;
    class var UndefinesText : string;
    class var SearchPathsText : string;
    class var ForbidText : string;
    class var AllowText : string;
    class var RulesFile : string;

    class procedure Reset;
    class function Command : TAnalyzerCommand;
    /// <summary>
    ///   The rules check will enforce, from the switches and the rules file together.
    ///   Raises ERulesError when the file cannot be read.
    /// </summary>
    class function Rules : IRuleSet;
    /// <summary>
    ///   Whatever is missing, described the way someone would fix it. The parser only
    ///   validates the default command's required arguments, so a command's own have to
    ///   be checked here.
    /// </summary>
    class function Validate(out error : string) : boolean;

    /// <summary>
    ///   A misspelled command is not recognised, so it lands in the project argument and
    ///   the real arguments then have nowhere to go - which makes the parser complain
    ///   about those instead of the actual mistake. Spotting it here means the message
    ///   can name the real problem. suggestion is the nearest command, or empty.
    /// </summary>
    class function IsProbablyMistypedCommand(out suggestion : string) : boolean;
    /// <summary>The commands worth listing, ie not the hidden aliases.</summary>
    class function CommandNames : TArray<string>;

    class function ToAnalyzerOptions : TAnalyzerOptions;
  end;

procedure ConfigureOptions;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.Math,
  System.SysUtils,
  VSoft.CommandLine.Options;

function SplitList(const value : string) : TArray<string>;
var
  entry : string;
  results : TArray<string>;
  count : integer;
begin
  SetLength(results, 0);
  count := 0;
  for entry in value.Split([';', ',']) do
    if Trim(entry) <> '' then
    begin
      SetLength(results, count + 1);
      results[count] := Trim(entry);
      Inc(count);
    end;
  result := results;
end;

class procedure TCommandLineOptions.Reset;
begin
  CommandName := '';
  ProjectFile := '';
  TargetUnit := '';
  FromUnit := '';
  OtherFile := '';
  HelpCommand := '';
  Config := '';
  Platform := '';
  Compiler := '';
  OutputFile := '';
  Deep := false;
  Quiet := false;
  MaxPaths := 5;
  Limit := 50;
  Depth := 3;
  DefinesText := '';
  UndefinesText := '';
  SearchPathsText := '';
  ForbidText := '';
  AllowText := '';
  RulesFile := '';
end;

class function TCommandLineOptions.Command : TAnalyzerCommand;
begin
  if SameText(CommandName, 'why') then
    result := acWhy
  else if SameText(CommandName, 'references') or SameText(CommandName, 'refs') then
    result := acReferences
  else if SameText(CommandName, 'check') then
    result := acCheck
  else if SameText(CommandName, 'cost') then
    result := acCost
  else if SameText(CommandName, 'deps') then
    result := acDeps
  else if SameText(CommandName, 'path') then
    result := acPath
  else if SameText(CommandName, 'cycles') then
    result := acCycles
  else if SameText(CommandName, 'diff') then
    result := acDiff
  else if SameText(CommandName, 'help') then
    result := acHelp
  else
    result := acAnalyze;
end;

class function TCommandLineOptions.Rules : IRuleSet;
var
  fromFile : IRuleSet;
begin
  fromFile := nil;
  if Trim(RulesFile) <> '' then
    fromFile := TRules.LoadFromFile(Trim(RulesFile));

  result := TRules.Combine(fromFile,
    TRules.FromSwitches(SplitList(ForbidText), SplitList(AllowText)));
end;

class function TCommandLineOptions.Validate(out error : string) : boolean;
begin
  error := '';
  if Command = acHelp then
    Exit(true);

  if Trim(ProjectFile) = '' then
    error := 'no project given - pass the .dproj or .dpr to analyse, or a .json graph'
  else if (Command in [acWhy, acReferences, acDeps]) and (Trim(TargetUnit) = '') then
    error := Format('the %s command needs a unit, eg "%s MyApp.dproj Vcl.Forms"',
      [LowerCase(CommandName), LowerCase(CommandName)])
  else if (Command = acPath) and ((Trim(FromUnit) = '') or (Trim(TargetUnit) = '')) then
    error := 'the path command needs two units, eg "path MyApp.dproj MyApp.Core Vcl.Forms"'
  else if (Command = acDiff) and (Trim(OtherFile) = '') then
    error := 'the diff command needs two things to compare, eg "diff before.json MyApp.dproj"'
  else if (Command = acCheck) and (Trim(ForbidText) = '') and (Trim(RulesFile) = '') then
    error := 'the check command needs rules - pass --forbid:Vcl.* or --rules:<file>';

  result := error = '';
end;

/// <summary>Levenshtein distance, so a single slip still finds the command meant.</summary>
function EditDistance(const left : string; const right : string) : integer;
var
  previous : TArray<integer>;
  current : TArray<integer>;
  i : integer;
  j : integer;
  cost : integer;
begin
  SetLength(previous, Length(right) + 1);
  SetLength(current, Length(right) + 1);
  for j := 0 to Length(right) do
    previous[j] := j;

  for i := 1 to Length(left) do
  begin
    current[0] := i;
    for j := 1 to Length(right) do
    begin
      if left[i] = right[j] then
        cost := 0
      else
        cost := 1;
      current[j] := Min(Min(current[j - 1] + 1, previous[j] + 1), previous[j - 1] + cost);
    end;
    previous := Copy(current);
  end;

  result := previous[Length(right)];
end;

/// <summary>
///   Whether an argument reads like something to analyse rather than a mistyped command.
///   An extension we know, or a file that is actually there, is good enough.
/// </summary>
function LooksLikeAProject(const value : string) : boolean;
var
  extension : string;
begin
  extension := LowerCase(ExtractFileExt(value));
  result := (extension = '.dproj') or (extension = '.dpr') or (extension = '.dpk') or
            (extension = '.json') or TFile.Exists(value) or TDirectory.Exists(value);
end;

class function TCommandLineOptions.CommandNames : TArray<string>;
var
  names : TStringList;
  definition : ICommandDefinition;
begin
  names := TStringList.Create;
  try
    names.Sorted := true;
    for definition in TOptionsRegistry.RegisteredCommands.Values do
      if definition.Visible then
        names.Add(definition.Name);
    result := names.ToStringArray;
  finally
    names.Free;
  end;
end;

class function TCommandLineOptions.IsProbablyMistypedCommand(out suggestion : string) : boolean;
var
  name : string;
  distance : integer;
  best : integer;
begin
  suggestion := '';
  // a recognised command, or nothing typed at all, is not this problem
  if (Command <> acAnalyze) or (Trim(ProjectFile) = '') or LooksLikeAProject(ProjectFile) then
    Exit(false);

  best := MaxInt;
  for name in CommandNames do
  begin
    distance := EditDistance(LowerCase(ProjectFile), LowerCase(name));
    // two slips is still recognisably the same word, more is a different one
    if (distance <= 2) and (distance < best) then
    begin
      best := distance;
      suggestion := name;
    end;
  end;

  result := true;
end;

class function TCommandLineOptions.ToAnalyzerOptions : TAnalyzerOptions;
begin
  result := Default(TAnalyzerOptions);
  result.ProjectFile := ProjectFile;
  result.Config := Config;
  result.Platform := Platform;
  result.Compiler := Compiler;
  result.OutputFile := OutputFile;
  result.Deep := Deep;
  result.ExtraDefines := SplitList(DefinesText);
  result.ExtraUndefines := SplitList(UndefinesText);
  result.ExtraSearchPaths := SplitList(SearchPathsText);
end;

/// <summary>
///   The project argument. Each command owns its own list of positionals, so this has to
///   be registered on every one of them rather than inherited from the default.
/// </summary>
procedure RegisterProjectArgument(const command : TCommandDefinition);
begin
  command.RegisterUnNamedOption<string>(
    'The .dproj or .dpr to analyse, or a .json graph saved earlier', 'project',
    procedure(const value : string)
    begin
      TCommandLineOptions.ProjectFile := value;
    end);
end;

procedure RegisterUnitArgument(const command : TCommandDefinition);
begin
  command.RegisterUnNamedOption<string>(
    'The unit to ask about. Accepts * and ?, eg Vcl.*', 'unit',
    procedure(const value : string)
    begin
      TCommandLineOptions.TargetUnit := value;
    end);
end;

/// <summary>
///   path takes two units. Positionals are filled in the order they were registered, so
///   this has to come before the one that takes the unit being headed for.
/// </summary>
procedure RegisterFromArgument(const command : TCommandDefinition);
begin
  command.RegisterUnNamedOption<string>(
    'The unit to start from', 'from',
    procedure(const value : string)
    begin
      TCommandLineOptions.FromUnit := value;
    end);
end;

procedure RegisterOtherProjectArgument(const command : TCommandDefinition);
begin
  command.RegisterUnNamedOption<string>(
    'The .dproj, .dpr or .json to compare against', 'other',
    procedure(const value : string)
    begin
      TCommandLineOptions.OtherFile := value;
    end);
end;

procedure ConfigureOptions;
var
  option : IOptionDefinition;
  command : TCommandDefinition;
begin
  TOptionsRegistry.DescriptionTab := 35;

  // With no command at all, analyse and report. Hidden because help for a command also
  // lists the default command's options, and this one is registered on every command -
  // so leaving it visible would print <project> twice. The usage preamble covers it.
  option := TOptionsRegistry.RegisterUnNamedOption<string>(
    'The .dproj or .dpr to analyse, or a .json graph saved earlier', 'project',
    procedure(const value : string)
    begin
      TCommandLineOptions.ProjectFile := value;
    end);
  option.Hidden := true;

  command := TOptionsRegistry.RegisterCommand('why', '',
    'Show the dependency chains that reach a unit', '',
    'why <project> <unit> [options]');
  RegisterProjectArgument(command);
  RegisterUnitArgument(command);
  command.Examples.Add('why MyApp.dproj Vcl.Forms');
  command.Examples.Add('why MyApp.dproj Vcl.* --maxpaths:1');

  command := TOptionsRegistry.RegisterCommand('references', 'refs',
    'Show the units that reference a unit', '',
    'references <project> <unit> [options]');
  RegisterProjectArgument(command);
  RegisterUnitArgument(command);
  command.Examples.Add('references MyApp.dproj System.Classes');
  command.Examples.Add('references graph.json Vcl.*');

  // VSoft.CommandLine keeps a command's alias on the definition but only registers the
  // name as a lookup key, so the short form has to be its own hidden command.
  command := TOptionsRegistry.RegisterCommand('refs', '',
    'Alias for references', '', 'refs <project> <unit> [options]', false);
  RegisterProjectArgument(command);
  RegisterUnitArgument(command);

  command := TOptionsRegistry.RegisterCommand('check', '',
    'Fail when the project reaches a unit a rule forbids', '',
    'check <project> [options]');
  RegisterProjectArgument(command);
  command.Examples.Add('check MyApp.dproj --forbid:Vcl.*,Fmx.*');
  command.Examples.Add('check MyApp.dproj --rules:dua.rules');

  command := TOptionsRegistry.RegisterCommand('cost', '',
    'Rank what each reference brings in, or the whole project', '',
    'cost <project> [unit] [options]');
  RegisterProjectArgument(command);
  RegisterUnitArgument(command);
  command.Examples.Add('cost MyApp.dproj MyApp');
  command.Examples.Add('cost MyApp.dproj');

  command := TOptionsRegistry.RegisterCommand('deps', '',
    'Show what a unit pulls in', '',
    'deps <project> <unit> [options]');
  RegisterProjectArgument(command);
  RegisterUnitArgument(command);
  command.Examples.Add('deps MyApp.dproj MyApp.Options');
  command.Examples.Add('deps MyApp.dproj MyApp.Options --depth:0');

  command := TOptionsRegistry.RegisterCommand('path', '',
    'Show the chains from one unit to another', '',
    'path <project> <from> <to> [options]');
  RegisterProjectArgument(command);
  RegisterFromArgument(command);
  RegisterUnitArgument(command);
  command.Examples.Add('path MyApp.dproj MyApp.Core Vcl.Forms');

  command := TOptionsRegistry.RegisterCommand('cycles', '',
    'Show units that reference each other in a circle', '',
    'cycles <project> [options]');
  RegisterProjectArgument(command);
  command.Examples.Add('cycles MyApp.dproj');

  command := TOptionsRegistry.RegisterCommand('diff', '',
    'Show what changed between two graphs', '',
    'diff <project> <other> [options]');
  RegisterProjectArgument(command);
  RegisterOtherProjectArgument(command);
  command.Examples.Add('diff before.json MyApp.dproj');

  command := TOptionsRegistry.RegisterCommand('help', 'h',
    'Show help for a command', '', 'help [command]');
  command.RegisterUnNamedOption<string>('The command to describe', 'command',
    procedure(const value : string)
    begin
      TCommandLineOptions.HelpCommand := value;
    end);

  // --- shared options, which any command resolves through the default one ---
  TOptionsRegistry.RegisterOption<string>('output', 'o',
    'Write the dependency graph as json to this file',
    procedure(const value : string)
    begin
      TCommandLineOptions.OutputFile := value;
    end);

  TOptionsRegistry.RegisterOption<string>('platform', 'p',
    'Target platform, eg Win32 or Win64. Defaults to the project default',
    procedure(const value : string)
    begin
      TCommandLineOptions.Platform := value;
    end);

  TOptionsRegistry.RegisterOption<string>('config', 'c',
    'Build configuration, eg Debug or Release. Defaults to the project default',
    procedure(const value : string)
    begin
      TCommandLineOptions.Config := value;
    end);

  TOptionsRegistry.RegisterOption<string>('compiler', '',
    'Delphi version, eg 13 or delphi12.0. Overrides what the dproj implies',
    procedure(const value : string)
    begin
      TCommandLineOptions.Compiler := value;
    end);

  TOptionsRegistry.RegisterOption<string>('define', 'd',
    'Extra conditional symbols, separated by ; or ,',
    procedure(const value : string)
    begin
      TCommandLineOptions.DefinesText := value;
    end);

  TOptionsRegistry.RegisterOption<string>('undefine', 'u',
    'Conditional symbols to remove, separated by ; or ,',
    procedure(const value : string)
    begin
      TCommandLineOptions.UndefinesText := value;
    end);

  TOptionsRegistry.RegisterOption<string>('searchpath', 's',
    'Extra unit search paths, separated by ; or ,',
    procedure(const value : string)
    begin
      TCommandLineOptions.SearchPathsText := value;
    end);

  option := TOptionsRegistry.RegisterOption<boolean>('deep', '',
    'Descend into the Delphi rtl and vcl sources as well',
    procedure(const value : boolean)
    begin
      TCommandLineOptions.Deep := value;
    end);
  option.HasValue := false;

  option := TOptionsRegistry.RegisterOption<boolean>('quiet', 'q',
    'Only report errors',
    procedure(const value : boolean)
    begin
      TCommandLineOptions.Quiet := value;
    end);
  option.HasValue := false;

  TOptionsRegistry.RegisterOption<integer>('maxpaths', '',
    'Chains to print per unit for why and path (default 5)',
    procedure(const value : integer)
    begin
      TCommandLineOptions.MaxPaths := value;
    end);

  TOptionsRegistry.RegisterOption<integer>('limit', 'l',
    'Rows to print per unit, 0 for all (default 50)',
    procedure(const value : integer)
    begin
      TCommandLineOptions.Limit := value;
    end);

  TOptionsRegistry.RegisterOption<integer>('depth', '',
    'How far down the deps tree to go, 0 for all (default 3)',
    procedure(const value : integer)
    begin
      TCommandLineOptions.Depth := value;
    end);

  TOptionsRegistry.RegisterOption<string>('forbid', '',
    'Units check must not reach, separated by ; or ,',
    procedure(const value : string)
    begin
      TCommandLineOptions.ForbidText := value;
    end);

  TOptionsRegistry.RegisterOption<string>('allow', '',
    'Exceptions to the forbidden units, separated by ; or ,',
    procedure(const value : string)
    begin
      TCommandLineOptions.AllowText := value;
    end);

  TOptionsRegistry.RegisterOption<string>('rules', '',
    'A file of check rules, one unit name or glob per line',
    procedure(const value : string)
    begin
      TCommandLineOptions.RulesFile := value;
    end);
end;

initialization
  TCommandLineOptions.Reset;
  ConfigureOptions;

end.
