program DelphiUsesAnalyzer.Tests;

{$IFNDEF TESTINSIGHT}
{$APPTYPE CONSOLE}
{$ENDIF}
{$STRONGLINKTYPES ON}

uses
  System.SysUtils,
  System.Diagnostics,
  {$IFDEF TESTINSIGHT}
  TestInsight.DUnitX,
  {$ELSE}
  DUnitX.Loggers.Console,
  DUnitX.Loggers.Xml.NUnit,
  {$ENDIF }
  DUnitX.TestFramework,
  DUA.Types in '..\Source\DUA.Types.pas',
  DUA.Defines in '..\Source\DUA.Defines.pas',
  DUA.Conditionals in '..\Source\DUA.Conditionals.pas',
  DUA.Scanner in '..\Source\DUA.Scanner.pas',
  DUA.Compiler.Versions in '..\Source\DUA.Compiler.Versions.pas',
  DUA.Project.MSBuild in '..\Source\DUA.Project.MSBuild.pas',
  DUA.Project.DProj in '..\Source\DUA.Project.DProj.pas',
  DUA.Compiler.Environment in '..\Source\DUA.Compiler.Environment.pas',
  DUA.SearchPath in '..\Source\DUA.SearchPath.pas',
  DUA.Graph in '..\Source\DUA.Graph.pas',
  DUA.Graph.Analysis in '..\Source\DUA.Graph.Analysis.pas',
  DUA.Analyzer in '..\Source\DUA.Analyzer.pas',
  DUA.Report.Json in '..\Source\DUA.Report.Json.pas',
  DUA.Report.Style in '..\Source\DUA.Report.Style.pas',
  DUA.Report.Console in '..\Source\DUA.Report.Console.pas',
  DUA.Rules in '..\Source\DUA.Rules.pas',
  DUA.Report.Queries in '..\Source\DUA.Report.Queries.pas',
  DUA.Options in '..\Source\DUA.Options.pas',
  DUA.Tests.Types in 'DUA.Tests.Types.pas',
  DUA.Tests.Options in 'DUA.Tests.Options.pas',
  DUA.Tests.ReportJson in 'DUA.Tests.ReportJson.pas',
  DUA.Tests.Rules in 'DUA.Tests.Rules.pas',
  DUA.Tests.Analyzer in 'DUA.Tests.Analyzer.pas',
  DUA.Tests.Graph in 'DUA.Tests.Graph.pas',
  DUA.Tests.GraphAnalysis in 'DUA.Tests.GraphAnalysis.pas',
  DUA.Tests.SearchPath in 'DUA.Tests.SearchPath.pas',
  DUA.Tests.Environment in 'DUA.Tests.Environment.pas',
  DUA.Tests.DProj in 'DUA.Tests.DProj.pas',
  DUA.Tests.MSBuild in 'DUA.Tests.MSBuild.pas',
  DUA.Tests.CompilerVersions in 'DUA.Tests.CompilerVersions.pas',
  DUA.Tests.Scanner in 'DUA.Tests.Scanner.pas',
  DUA.Tests.Conditionals in 'DUA.Tests.Conditionals.pas',
  DUA.Tests.Defines in 'DUA.Tests.Defines.pas';

{ keep comment here to protect the following conditional from being removed by the IDE when adding a unit }
{$IFNDEF TESTINSIGHT}
var
  runner : ITestRunner;
  results : IRunResults;
  logger : ITestLogger;
  nunitLogger : ITestLogger;
  stopwatch : TStopwatch;
{$ENDIF}
begin
{$IFDEF TESTINSIGHT}
  TestInsight.DUnitX.RunRegisteredTests;
{$ELSE}
  try
    //Check command line options, will exit if invalid
    TDUnitX.CheckCommandLine;
    //Create the test runner
    runner := TDUnitX.CreateRunner;
    //Tell the runner to use RTTI to find Fixtures
    runner.UseRTTI := False;
    //When true, Assertions must be made during tests;
    runner.FailsOnNoAsserts := False;

    TDUnitX.Options.ExitBehavior := TDUnitXExitBehavior.Pause;

    //tell the runner how we will log things
    //Log to the console window if desired
    TDUnitX.Options.ConsoleMode := TDunitXConsoleMode.Quiet;
    if TDUnitX.Options.ConsoleMode <> TDunitXConsoleMode.Off then
    begin
      ReportMemoryLeaksOnShutdown := True;
      logger := TDUnitXConsoleLogger.Create(TDUnitX.Options.ConsoleMode = TDunitXConsoleMode.Verbose);
      runner.AddLogger(logger);
    end;
    //Generate an NUnit compatible XML File
    if TDUnitX.Options.XMLOutputFile <> '' then
    begin
      nunitLogger := TDUnitXXMLNUnitFileLogger.Create(TDUnitX.Options.XMLOutputFile);
      runner.AddLogger(nunitLogger);
    end;

    //Run tests
    stopwatch := TStopwatch.StartNew;
    results := runner.Execute;
    stopwatch.Stop;
    if not results.AllPassed then
      System.ExitCode := EXIT_ERRORS;

    System.Writeln(Format('Tests completed in : %dms', [stopwatch.ElapsedMilliseconds]));

    {$IFNDEF CI}
    //We don't want this happening when running under CI.
    if TDUnitX.Options.ExitBehavior = TDUnitXExitBehavior.Pause then
    begin
      System.Write('Done.. press <Enter> key to quit.');
      System.Readln;
    end;
    {$ENDIF}
  except
    on E : Exception do
      System.Writeln(E.ClassName, ': ', E.Message);
  end;
{$ENDIF}
end.
