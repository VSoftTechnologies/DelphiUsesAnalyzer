unit DUA.Tests.Options;

interface

uses
  DUnitX.TestFramework,
  DUA.Options;

type
  /// <summary>
  ///   The command line itself. VSoft.CommandLine can parse a TStrings rather than the
  ///   real arguments, so the shape of the command line is testable without launching
  ///   anything.
  /// </summary>
  [TestFixture]
  TCommandLineTests = class
  private
    function Parse(const args : array of string) : string;
    procedure AssertCommand(const expected : TAnalyzerCommand;
                            const args : array of string);
    function ErrorFrom(const args : array of string) : string;
  public
    [Setup]
    procedure Setup;

    // --- with no command, analyse ---
    [Test] procedure NoCommandMeansAnalyse;
    [Test] procedure NoCommandTakesTheProjectAsItsArgument;

    // --- commands ---
    [Test] procedure WhyCommandTakesAProjectAndAUnit;
    [Test] procedure ReferencesCommandTakesAProjectAndAUnit;
    [Test] procedure ReferencesHasAShortAlias;
    [Test] procedure HelpCommandTakesTheCommandToDescribe;
    [Test] procedure CommandNamesAreCaseInsensitive;

    // --- shared options resolve through the default command ---
    [Test] procedure ACommandStillAcceptsTheSharedOptions;
    [Test] procedure OptionsMayComeBeforeThePositionals;
    [Test] procedure SwitchesNeedNoValue;
    [Test] procedure ListOptionsAreSplit;

    // --- what is missing, and how it reads ---
    [Test] procedure AnalyseWithoutAProjectIsRejected;
    [Test] procedure WhyWithoutAUnitIsRejected;
    [Test] procedure ReferencesWithoutAUnitIsRejected;
    [Test] procedure WhyWithBothArgumentsIsAccepted;
    [Test] procedure HelpNeedsNothing;
    [Test] procedure AnUnknownOptionIsAnError;

    // --- a misspelled command lands in the project argument, so catch it ---
    [Test] procedure AMisspeltCommandIsRecognisedAsSuch;
    [Test] procedure AMisspeltCommandSuggestsTheRealOne;
    [Test] procedure AWordUnlikeAnyCommandStillReportsUnknownButSuggestsNothing;
    [Test] procedure ARealProjectIsNotMistakenForACommand;
    [Test] procedure AnExistingFileIsNotMistakenForACommand;
    [Test] procedure ARealCommandIsNotFlagged;
    [Test] procedure NothingTypedIsNotFlagged;
    [Test] procedure TheListedCommandsExcludeHiddenAliases;

    // --- the query commands ---
    [Test] procedure CheckIsACommand;
    [Test] procedure CostIsACommand;
    [Test] procedure DepsIsACommand;
    [Test] procedure PathIsACommand;
    [Test] procedure CyclesIsACommand;
    [Test] procedure DiffIsACommand;
    [Test] procedure EveryQueryCommandIsListed;

    // --- what each command needs ---
    [Test] procedure DepsNeedsAUnit;
    [Test] procedure PathNeedsBothUnits;
    [Test] procedure PathTakesTheUnitsInOrder;
    [Test] procedure DiffNeedsSomethingToCompareAgainst;
    [Test] procedure CheckNeedsRules;
    [Test] procedure CheckAcceptsRulesFromASwitch;
    [Test] procedure CheckAcceptsARulesFile;
    [Test] procedure CostDoesNotNeedAUnit;
    [Test] procedure CyclesDoesNotNeedAUnit;

    // --- the new options ---
    [Test] procedure ForbidIsCollected;
    [Test] procedure AllowIsCollected;
    [Test] procedure DepthIsCollected;
    [Test] procedure RulesComeFromSwitches;
    [Test] procedure AnAllowSwitchExcusesAForbidSwitch;

    // --- defaults ---
    [Test] procedure MaxPathsDefaultsToFive;
    [Test] procedure LimitDefaultsToFifty;
    [Test] procedure DepthDefaultsToThree;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.SysUtils,
  System.TypInfo,
  VSoft.CommandLine.Options,
  DUA.Analyzer;

{ TCommandLineTests }

procedure TCommandLineTests.Setup;
begin
  // the registry is global, so each test starts from a known state
  TCommandLineOptions.Reset;
end;

/// <summary>Parses and returns the command name, or the parse errors when there are any.</summary>
function TCommandLineTests.Parse(const args : array of string) : string;
var
  values : TStringList;
  arg : string;
  parseResult : ICommandLineParseResult;
begin
  values := TStringList.Create;
  try
    for arg in args do
      values.Add(arg);
    parseResult := TOptionsRegistry.Parse(values);
    if parseResult.HasErrors then
      Exit('ERROR: ' + parseResult.ErrorText);
    TCommandLineOptions.CommandName := parseResult.Command;
    result := parseResult.Command;
  finally
    values.Free;
  end;
end;

/// <summary>Whatever the command line is missing, once parsing itself has succeeded.</summary>
function TCommandLineTests.ErrorFrom(const args : array of string) : string;
begin
  result := Parse(args);
  if result.StartsWith('ERROR:') then
    Exit;
  if TCommandLineOptions.Validate(result) then
    result := '';
end;

procedure TCommandLineTests.NoCommandMeansAnalyse;
begin
  Parse(['MyApp.dproj']);
  Assert.AreEqual(GetEnumName(TypeInfo(TAnalyzerCommand), Ord(acAnalyze)),
    GetEnumName(TypeInfo(TAnalyzerCommand), Ord(TCommandLineOptions.Command)));
end;

procedure TCommandLineTests.NoCommandTakesTheProjectAsItsArgument;
begin
  Parse(['MyApp.dproj']);
  Assert.AreEqual('MyApp.dproj', TCommandLineOptions.ProjectFile);
end;

procedure TCommandLineTests.WhyCommandTakesAProjectAndAUnit;
begin
  Assert.AreEqual('why', Parse(['why', 'MyApp.dproj', 'Vcl.Forms']));
  Assert.AreEqual('MyApp.dproj', TCommandLineOptions.ProjectFile);
  Assert.AreEqual('Vcl.Forms', TCommandLineOptions.TargetUnit);
end;

procedure TCommandLineTests.ReferencesCommandTakesAProjectAndAUnit;
begin
  Assert.AreEqual('references', Parse(['references', 'MyApp.dproj', 'System.Classes']));
  Assert.AreEqual('MyApp.dproj', TCommandLineOptions.ProjectFile);
  Assert.AreEqual('System.Classes', TCommandLineOptions.TargetUnit);
end;

procedure TCommandLineTests.ReferencesHasAShortAlias;
begin
  Parse(['refs', 'MyApp.dproj', 'System.Classes']);
  Assert.AreEqual(GetEnumName(TypeInfo(TAnalyzerCommand), Ord(acReferences)),
    GetEnumName(TypeInfo(TAnalyzerCommand), Ord(TCommandLineOptions.Command)));
end;

procedure TCommandLineTests.HelpCommandTakesTheCommandToDescribe;
begin
  Assert.AreEqual('help', Parse(['help', 'why']));
  Assert.AreEqual('why', TCommandLineOptions.HelpCommand);
end;

procedure TCommandLineTests.CommandNamesAreCaseInsensitive;
begin
  Parse(['WHY', 'MyApp.dproj', 'Vcl.Forms']);
  Assert.AreEqual(GetEnumName(TypeInfo(TAnalyzerCommand), Ord(acWhy)),
    GetEnumName(TypeInfo(TAnalyzerCommand), Ord(TCommandLineOptions.Command)));
end;

procedure TCommandLineTests.ACommandStillAcceptsTheSharedOptions;
begin
  // the shared options live on the default command, and a named command falls back to it
  Parse(['why', 'MyApp.dproj', 'Vcl.Forms', '--platform:Win64', '--config:Release',
         '--maxpaths:3']);
  Assert.AreEqual('Win64', TCommandLineOptions.Platform);
  Assert.AreEqual('Release', TCommandLineOptions.Config);
  Assert.AreEqual(3, TCommandLineOptions.MaxPaths);
end;

procedure TCommandLineTests.OptionsMayComeBeforeThePositionals;
begin
  Parse(['references', '--limit:5', 'MyApp.dproj', 'Vcl.*']);
  Assert.AreEqual('MyApp.dproj', TCommandLineOptions.ProjectFile);
  Assert.AreEqual('Vcl.*', TCommandLineOptions.TargetUnit);
  Assert.AreEqual(5, TCommandLineOptions.Limit);
end;

procedure TCommandLineTests.SwitchesNeedNoValue;
begin
  Parse(['MyApp.dproj', '--deep', '--quiet']);
  Assert.IsTrue(TCommandLineOptions.Deep, 'deep');
  Assert.IsTrue(TCommandLineOptions.Quiet, 'quiet');
end;

procedure TCommandLineTests.ListOptionsAreSplit;
var
  options : TAnalyzerOptions;
begin
  Parse(['MyApp.dproj', '--define:ALPHA;BETA', '--searchpath:C:\a,C:\b']);
  options := TCommandLineOptions.ToAnalyzerOptions;

  Assert.AreEqual<integer>(2, Length(options.ExtraDefines));
  Assert.AreEqual('ALPHA', options.ExtraDefines[0]);
  Assert.AreEqual('BETA', options.ExtraDefines[1]);
  Assert.AreEqual<integer>(2, Length(options.ExtraSearchPaths));
  Assert.AreEqual('C:\b', options.ExtraSearchPaths[1]);
end;

procedure TCommandLineTests.AnalyseWithoutAProjectIsRejected;
begin
  Assert.Contains(ErrorFrom([]), 'no project given');
end;

procedure TCommandLineTests.WhyWithoutAUnitIsRejected;
var
  error : string;
begin
  // the parser only enforces the default command's arguments, so this is our own check
  error := ErrorFrom(['why', 'MyApp.dproj']);
  Assert.Contains(error, 'needs a unit');
  Assert.Contains(error, 'why');
end;

procedure TCommandLineTests.ReferencesWithoutAUnitIsRejected;
begin
  Assert.Contains(ErrorFrom(['references', 'MyApp.dproj']), 'needs a unit');
end;

procedure TCommandLineTests.WhyWithBothArgumentsIsAccepted;
begin
  Assert.AreEqual('', ErrorFrom(['why', 'MyApp.dproj', 'Vcl.Forms']));
end;

procedure TCommandLineTests.HelpNeedsNothing;
begin
  Assert.AreEqual('', ErrorFrom(['help']));
end;

procedure TCommandLineTests.AnUnknownOptionIsAnError;
begin
  Assert.StartsWith('ERROR:', Parse(['MyApp.dproj', '--nosuchoption:1']));
end;

procedure TCommandLineTests.AMisspeltCommandIsRecognisedAsSuch;
var
  suggestion : string;
begin
  Parse(['refernences', 'graph.json', 'VSoft.Core.Actions.Interfaces']);
  Assert.IsTrue(TCommandLineOptions.IsProbablyMistypedCommand(suggestion));
end;

procedure TCommandLineTests.AMisspeltCommandSuggestsTheRealOne;
var
  suggestion : string;
begin
  Parse(['refernences', 'graph.json', 'Something']);
  TCommandLineOptions.IsProbablyMistypedCommand(suggestion);
  Assert.AreEqual('references', suggestion);

  TCommandLineOptions.Reset;
  Parse(['wyh', 'graph.json', 'Something']);
  TCommandLineOptions.IsProbablyMistypedCommand(suggestion);
  Assert.AreEqual('why', suggestion);
end;

procedure TCommandLineTests.AWordUnlikeAnyCommandStillReportsUnknownButSuggestsNothing;
var
  suggestion : string;
begin
  Parse(['banana']);
  Assert.IsTrue(TCommandLineOptions.IsProbablyMistypedCommand(suggestion));
  Assert.AreEqual('', suggestion, 'guessing at something this far off would be noise');
end;

procedure TCommandLineTests.ARealProjectIsNotMistakenForACommand;
var
  suggestion : string;
  name : string;
begin
  // these need not exist - the extension is enough to say what was meant
  for name in TArray<string>.Create('MyApp.dproj', 'MyApp.dpr', 'MyApp.dpk', 'graph.json') do
  begin
    TCommandLineOptions.Reset;
    Parse([name]);
    Assert.IsFalse(TCommandLineOptions.IsProbablyMistypedCommand(suggestion), name);
  end;
end;

procedure TCommandLineTests.AnExistingFileIsNotMistakenForACommand;
var
  suggestion : string;
  temporary : string;
begin
  // an extensionless path that is really there is a project, however odd it looks
  temporary := TPath.Combine(TPath.GetTempPath, 'dua-cmd-' + TGuid.NewGuid.ToString);
  TFile.WriteAllText(temporary, 'x');
  try
    Parse([temporary]);
    Assert.IsFalse(TCommandLineOptions.IsProbablyMistypedCommand(suggestion));
  finally
    TFile.Delete(temporary);
  end;
end;

procedure TCommandLineTests.ARealCommandIsNotFlagged;
var
  suggestion : string;
begin
  Parse(['references', 'graph.json', 'System.Classes']);
  Assert.IsFalse(TCommandLineOptions.IsProbablyMistypedCommand(suggestion));
end;

procedure TCommandLineTests.NothingTypedIsNotFlagged;
var
  suggestion : string;
begin
  Parse([]);
  Assert.IsFalse(TCommandLineOptions.IsProbablyMistypedCommand(suggestion),
    'with no arguments the missing project is the thing to report');
end;

procedure TCommandLineTests.TheListedCommandsExcludeHiddenAliases;
var
  names : string;
begin
  names := string.Join(',', TCommandLineOptions.CommandNames);
  Assert.Contains(names, 'why');
  Assert.Contains(names, 'references');
  Assert.Contains(names, 'help');
  Assert.DoesNotContain(names, 'refs', 'refs is a hidden alias, not a command to advertise');
end;

/// <summary>Compares commands by name so a failure says which one it got.</summary>
procedure TCommandLineTests.AssertCommand(const expected : TAnalyzerCommand;
  const args : array of string);
begin
  Parse(args);
  Assert.AreEqual(GetEnumName(TypeInfo(TAnalyzerCommand), Ord(expected)),
    GetEnumName(TypeInfo(TAnalyzerCommand), Ord(TCommandLineOptions.Command)));
end;

procedure TCommandLineTests.CheckIsACommand;
begin
  AssertCommand(acCheck, ['check', 'MyApp.dproj', '--forbid:Vcl.*']);
end;

procedure TCommandLineTests.CostIsACommand;
begin
  AssertCommand(acCost, ['cost', 'MyApp.dproj']);
end;

procedure TCommandLineTests.DepsIsACommand;
begin
  AssertCommand(acDeps, ['deps', 'MyApp.dproj', 'MyApp.Options']);
end;

procedure TCommandLineTests.PathIsACommand;
begin
  AssertCommand(acPath, ['path', 'MyApp.dproj', 'MyApp.Core', 'Vcl.Forms']);
end;

procedure TCommandLineTests.CyclesIsACommand;
begin
  AssertCommand(acCycles, ['cycles', 'MyApp.dproj']);
end;

procedure TCommandLineTests.DiffIsACommand;
begin
  AssertCommand(acDiff, ['diff', 'before.json', 'MyApp.dproj']);
end;

procedure TCommandLineTests.EveryQueryCommandIsListed;
var
  names : string;
  name : string;
begin
  // a command nobody is told about may as well not be there, and the typo suggestion
  // list is built from the same place
  names := string.Join(',', TCommandLineOptions.CommandNames);
  for name in ['check', 'cost', 'deps', 'path', 'cycles', 'diff'] do
    Assert.Contains(names, name, name);
end;

procedure TCommandLineTests.DepsNeedsAUnit;
begin
  Assert.Contains(ErrorFrom(['deps', 'MyApp.dproj']), 'needs a unit');
end;

procedure TCommandLineTests.PathNeedsBothUnits;
begin
  Assert.Contains(ErrorFrom(['path', 'MyApp.dproj']), 'needs two units');
  Assert.Contains(ErrorFrom(['path', 'MyApp.dproj', 'MyApp.Core']), 'needs two units');
end;

procedure TCommandLineTests.PathTakesTheUnitsInOrder;
begin
  Parse(['path', 'MyApp.dproj', 'MyApp.Core', 'Vcl.Forms']);
  Assert.AreEqual('MyApp.Core', TCommandLineOptions.FromUnit, 'from');
  Assert.AreEqual('Vcl.Forms', TCommandLineOptions.TargetUnit, 'to');
end;

procedure TCommandLineTests.DiffNeedsSomethingToCompareAgainst;
begin
  Assert.Contains(ErrorFrom(['diff', 'before.json']), 'two things to compare');
end;

procedure TCommandLineTests.CheckNeedsRules;
begin
  // a check with no rules would pass every build, which is worse than not running it
  Assert.Contains(ErrorFrom(['check', 'MyApp.dproj']), 'needs rules');
end;

procedure TCommandLineTests.CheckAcceptsRulesFromASwitch;
begin
  Assert.AreEqual('', ErrorFrom(['check', 'MyApp.dproj', '--forbid:Vcl.*']));
end;

procedure TCommandLineTests.CheckAcceptsARulesFile;
begin
  Assert.AreEqual('', ErrorFrom(['check', 'MyApp.dproj', '--rules:dua.rules']));
end;

procedure TCommandLineTests.CostDoesNotNeedAUnit;
begin
  Assert.AreEqual('', ErrorFrom(['cost', 'MyApp.dproj']));
end;

procedure TCommandLineTests.CyclesDoesNotNeedAUnit;
begin
  Assert.AreEqual('', ErrorFrom(['cycles', 'MyApp.dproj']));
end;

procedure TCommandLineTests.ForbidIsCollected;
begin
  Parse(['check', 'MyApp.dproj', '--forbid:Vcl.*;Fmx.*']);
  Assert.AreEqual('Vcl.*;Fmx.*', TCommandLineOptions.ForbidText);
end;

procedure TCommandLineTests.AllowIsCollected;
begin
  Parse(['check', 'MyApp.dproj', '--forbid:Vcl.*', '--allow:Vcl.Graphics']);
  Assert.AreEqual('Vcl.Graphics', TCommandLineOptions.AllowText);
end;

procedure TCommandLineTests.DepthIsCollected;
begin
  Parse(['deps', 'MyApp.dproj', 'MyApp.Options', '--depth:0']);
  Assert.AreEqual(0, TCommandLineOptions.Depth);
end;

procedure TCommandLineTests.RulesComeFromSwitches;
begin
  Parse(['check', 'MyApp.dproj', '--forbid:Vcl.*,Fmx.*']);
  Assert.AreEqual<integer>(2, TCommandLineOptions.Rules.ForbidCount);
end;

procedure TCommandLineTests.AnAllowSwitchExcusesAForbidSwitch;
begin
  Parse(['check', 'MyApp.dproj', '--forbid:Vcl.*', '--allow:Vcl.Graphics']);
  Assert.AreEqual('', TCommandLineOptions.Rules.ViolatedBy('Vcl.Graphics'));
  Assert.AreNotEqual('', TCommandLineOptions.Rules.ViolatedBy('Vcl.Forms'));
end;

procedure TCommandLineTests.DepthDefaultsToThree;
begin
  Parse(['deps', 'MyApp.dproj', 'MyApp.Options']);
  Assert.AreEqual(3, TCommandLineOptions.Depth);
end;

procedure TCommandLineTests.MaxPathsDefaultsToFive;
begin
  Parse(['why', 'MyApp.dproj', 'Vcl.Forms']);
  Assert.AreEqual(5, TCommandLineOptions.MaxPaths);
end;

procedure TCommandLineTests.LimitDefaultsToFifty;
begin
  Parse(['references', 'MyApp.dproj', 'Vcl.Forms']);
  Assert.AreEqual(50, TCommandLineOptions.Limit);
end;

initialization
  TDUnitX.RegisterTestFixture(TCommandLineTests);

end.
