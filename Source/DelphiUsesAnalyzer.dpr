program DelphiUsesAnalyzer;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Diagnostics,
  VSoft.CommandLine.Options,
  DUA.Types in 'DUA.Types.pas',
  DUA.Defines in 'DUA.Defines.pas',
  DUA.Conditionals in 'DUA.Conditionals.pas',
  DUA.Scanner in 'DUA.Scanner.pas',
  DUA.Compiler.Versions in 'DUA.Compiler.Versions.pas',
  DUA.Compiler.Environment in 'DUA.Compiler.Environment.pas',
  DUA.Project.MSBuild in 'DUA.Project.MSBuild.pas',
  DUA.Project.DProj in 'DUA.Project.DProj.pas',
  DUA.SearchPath in 'DUA.SearchPath.pas',
  DUA.Graph in 'DUA.Graph.pas',
  DUA.Graph.Analysis in 'DUA.Graph.Analysis.pas',
  DUA.Analyzer in 'DUA.Analyzer.pas',
  DUA.Report.Json in 'DUA.Report.Json.pas',
  DUA.Report.Style in 'DUA.Report.Style.pas',
  DUA.Report.Console in 'DUA.Report.Console.pas',
  DUA.Rules in 'DUA.Rules.pas',
  DUA.Report.Queries in 'DUA.Report.Queries.pas',
  DUA.Options in 'DUA.Options.pas';

procedure PrintUsage(const forCommand : string);
begin
  Writeln('DelphiUsesAnalyzer - build a unit dependency graph for a Delphi project');
  Writeln('');
  if forCommand = '' then
  begin
    Writeln('With no command it analyses a project and reports:');
    Writeln('');
    Writeln('  DelphiUsesAnalyzer <project> [options]');
    Writeln('');
    Writeln('<project> is a .dproj, a .dpr, or a .json graph saved earlier with --output.');
    Writeln('');
  end;
  if forCommand <> '' then
    TOptionsRegistry.PrintUsage(forCommand,
      procedure(const value : string)
      begin
        Writeln(value);
      end)
  else
    TOptionsRegistry.PrintUsage(
      procedure(const value : string)
      begin
        Writeln(value);
      end);
end;

/// <summary>
///   A graph, however it has to be got hold of. A saved one is read back rather than
///   walked again, which is what makes a query answer instantly on a large project.
///   diff needs this twice, which is why it is a function rather than written inline.
/// </summary>
function AcquireGraph(const projectFile : string; out shownTarget : boolean) : IAnalysisResult;
var
  running : TAnalyzerOptions;
  analyzer : IAnalyzer;
begin
  shownTarget := false;

  if SameText(ExtractFileExt(projectFile), '.json') then
    Exit(TJsonReport.Load(projectFile));

  running := TCommandLineOptions.ToAnalyzerOptions;
  running.ProjectFile := projectFile;

  analyzer := TAnalyzer.Create;
  if TCommandLineOptions.Quiet then
    result := analyzer.Analyze(running)
  else
    result := TConsoleReport.RunWithProgress(analyzer, running, shownTarget);
end;

var
  parseResult : ICommandLineParseResult;
  analysis : IAnalysisResult;
  other : IAnalysisResult;
  options : TAnalyzerOptions;
  stopwatch : TStopwatch;
  fromSavedGraph : boolean;
  targetShown : boolean;
  otherShown : boolean;
  validationError : string;
  suggestion : string;
begin
  try
    parseResult := TOptionsRegistry.Parse;
    TCommandLineOptions.CommandName := parseResult.Command;

    // A misspelled command is not recognised, so it is taken as the project and the real
    // arguments are then left over - the parser would blame those rather than the typo.
    if TCommandLineOptions.IsProbablyMistypedCommand(suggestion) then
    begin
      Writeln(Format('Unknown command "%s".', [TCommandLineOptions.ProjectFile]));
      if suggestion <> '' then
        Writeln(Format('Did you mean "%s"?', [suggestion]));
      Writeln('');
      Writeln('Commands: ' + string.Join(', ', TCommandLineOptions.CommandNames));
      Writeln('');
      Writeln('To analyse a project, pass it directly:');
      Writeln('  DelphiUsesAnalyzer <project> [options]');
      ExitCode := 1;
      Exit;
    end;

    if parseResult.HasErrors then
    begin
      Writeln(parseResult.ErrorText);
      PrintUsage(parseResult.Command);
      ExitCode := 1;
      Exit;
    end;

    if TCommandLineOptions.Command = acHelp then
    begin
      PrintUsage(TCommandLineOptions.HelpCommand);
      Exit;
    end;

    // the parser only enforces the default command's arguments, so a command's own
    // have to be checked here
    if not TCommandLineOptions.Validate(validationError) then
    begin
      Writeln(validationError);
      Writeln('');
      PrintUsage(parseResult.Command);
      ExitCode := 1;
      Exit;
    end;

    options := TCommandLineOptions.ToAnalyzerOptions;

    stopwatch := TStopwatch.StartNew;
    fromSavedGraph := SameText(ExtractFileExt(options.ProjectFile), '.json');
    analysis := AcquireGraph(options.ProjectFile, targetShown);
    stopwatch.Stop;

    // diff has two graphs and no single thing to summarise, so it prints its own
    // preamble rather than one side's
    if not TCommandLineOptions.Quiet and (TCommandLineOptions.Command <> acDiff) then
    begin
      // the walk shows the target before it starts, so only print it here when it did not
      if not targetShown then
        TConsoleReport.WriteTarget(analysis);
      TConsoleReport.WriteSummary(analysis);
      if fromSavedGraph then
        TConsoleReport.WriteElapsed(stopwatch.ElapsedMilliseconds,
          ExtractFileName(options.ProjectFile))
      else
        TConsoleReport.WriteElapsed(stopwatch.ElapsedMilliseconds, '');
      TConsoleReport.WriteWarnings(analysis, 20);
    end;

    if (options.OutputFile <> '') and not fromSavedGraph then
    begin
      TJsonReport.WriteToFile(analysis, options.OutputFile);
      if not TCommandLineOptions.Quiet then
      begin
        Writeln('');
        Writeln('Wrote ' + options.OutputFile);
      end;
    end;

    case TCommandLineOptions.Command of
      acWhy : TConsoleReport.WriteWhy(analysis, TCommandLineOptions.TargetUnit,
                TCommandLineOptions.MaxPaths);
      acReferences : TConsoleReport.WriteReferences(analysis, TCommandLineOptions.TargetUnit,
                       TCommandLineOptions.Limit);
      acPath : TConsoleReport.WritePath(analysis, TCommandLineOptions.FromUnit,
                 TCommandLineOptions.TargetUnit, TCommandLineOptions.MaxPaths);
      acCost : TQueryReport.WriteCost(analysis, TCommandLineOptions.TargetUnit,
                 TCommandLineOptions.Limit);
      acDeps : TQueryReport.WriteDeps(analysis, TCommandLineOptions.TargetUnit,
                 TCommandLineOptions.Depth, TCommandLineOptions.Limit);
      acCycles : TQueryReport.WriteCycles(analysis, TCommandLineOptions.Limit);

      // the only command that can fail, and the only reason to run this in a build
      acCheck :
        if not TQueryReport.WriteCheck(analysis, TCommandLineOptions.Rules,
                 TCommandLineOptions.Limit) then
          ExitCode := 1;

      acDiff :
        begin
          other := AcquireGraph(TCommandLineOptions.OtherFile, otherShown);
          TQueryReport.WriteDiff(analysis, other,
            FileNameOnly(options.ProjectFile),
            FileNameOnly(TCommandLineOptions.OtherFile),
            TCommandLineOptions.Limit);
        end;
    end;
  except
    // Our own errors are written to be read, so the class name in front of them is
    // noise. Anything else is a surprise, and there the class name is the useful part.
    on e : EAnalyzerError do
    begin
      Writeln(ErrOutput, e.Message);
      ExitCode := 1;
    end;
    on e : EJsonReportError do
    begin
      Writeln(ErrOutput, e.Message);
      ExitCode := 1;
    end;
    on e : ERulesError do
    begin
      Writeln(ErrOutput, e.Message);
      ExitCode := 1;
    end;
    on e : Exception do
    begin
      Writeln(ErrOutput, e.ClassName + ': ' + e.Message);
      ExitCode := 1;
    end;
  end;
end.
