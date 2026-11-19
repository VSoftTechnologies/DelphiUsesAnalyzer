unit DUA.Tests.ReportStyle;

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>
  ///   How the reports write a file down. A bare file name cannot tell two copies of a
  ///   unit apart, so --fullpaths has to reach every place a report writes one.
  /// </summary>
  [TestFixture]
  TReportStyleTests = class
  public
    [TearDown]
    procedure TearDown;

    [Test] procedure ALocationIsTheFileNameByDefault;
    [Test] procedure ALocationIsTheWholePathWithFullPaths;
    [Test] procedure ALocationWithForwardSlashesIsStillShortened;
    [Test] procedure ALocationIsSafeAsMarkup;

    [Test] procedure NoResolvedFileWithoutFullPaths;
    [Test] procedure TheResolvedFileWithFullPaths;
    [Test] procedure AnUnresolvedUnitHasNoResolvedFile;
    [Test] procedure AResolvedFileIsSafeAsMarkup;
  end;

implementation

uses
  DUA.Graph,
  DUA.Report.Style;

{ TReportStyleTests }

procedure TReportStyleTests.TearDown;
begin
  // the setting is shared by every report, so leave it as the next test expects
  SetFullPaths(false);
end;

procedure TReportStyleTests.ALocationIsTheFileNameByDefault;
begin
  Assert.AreEqual('Unit1.pas(12)', SourceLocation('C:\src\App\Unit1.pas', 12));
end;

procedure TReportStyleTests.ALocationIsTheWholePathWithFullPaths;
begin
  SetFullPaths(true);
  Assert.AreEqual('C:\src\App\Unit1.pas(12)', SourceLocation('C:\src\App\Unit1.pas', 12));
end;

procedure TReportStyleTests.ALocationWithForwardSlashesIsStillShortened;
begin
  Assert.AreEqual('Unit1.pas(3)', SourceLocation('C:/src/App/Unit1.pas', 3));
end;

procedure TReportStyleTests.ALocationIsSafeAsMarkup;
begin
  // a folder with a bracket in it would otherwise be read as a style tag
  SetFullPaths(true);
  Assert.AreEqual('C:\src[[old]]\Unit1.pas(3)', SourceLocation('C:\src[old]\Unit1.pas', 3));
end;

procedure TReportStyleTests.NoResolvedFileWithoutFullPaths;
var
  node : TGraphNode;
begin
  node := TGraphNode.Create('Unit1');
  try
    node.FileName := 'C:\src\App\Unit1.pas';
    Assert.AreEqual('', ResolvedFile(node));
  finally
    node.Free;
  end;
end;

procedure TReportStyleTests.TheResolvedFileWithFullPaths;
var
  node : TGraphNode;
begin
  SetFullPaths(true);
  node := TGraphNode.Create('Unit1');
  try
    node.FileName := 'C:\src\App\Unit1.pas';
    Assert.AreEqual('C:\src\App\Unit1.pas', ResolvedFile(node));
  finally
    node.Free;
  end;
end;

procedure TReportStyleTests.AnUnresolvedUnitHasNoResolvedFile;
var
  node : TGraphNode;
begin
  SetFullPaths(true);
  node := TGraphNode.Create('Missing');
  try
    Assert.AreEqual('', ResolvedFile(node));
  finally
    node.Free;
  end;
end;

procedure TReportStyleTests.AResolvedFileIsSafeAsMarkup;
var
  node : TGraphNode;
begin
  SetFullPaths(true);
  node := TGraphNode.Create('Unit1');
  try
    node.FileName := 'C:\src[old]\Unit1.pas';
    Assert.AreEqual('C:\src[[old]]\Unit1.pas', ResolvedFile(node));
  finally
    node.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TReportStyleTests);

end.
