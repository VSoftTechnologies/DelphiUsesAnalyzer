unit DUA.Tests.SearchPath;

interface

uses
  DUnitX.TestFramework,
  DUA.SearchPath;

type
  /// <summary>
  ///   Resolving a unit name to a file the way the compiler would. This is the piece
  ///   with no prior art, so it gets a real directory tree to work against rather than
  ///   a mock: the ordering rules only mean anything against a real file system.
  /// </summary>
  [TestFixture]
  TUnitResolverTests = class
  private
    FRoot : string;
    FResolver : IUnitResolver;
    procedure GivenFile(const relativePath : string);
    function PathOf(const relativeFolder : string) : string;
    function Resolve(const unitName : string) : TResolvedUnit;
    function ResolveFrom(const unitName : string; const referencingFile : string) : TResolvedUnit;
    function CanResolve(const unitName : string) : boolean;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    // --- the basics ---
    [Test] procedure ResolvesAUnitOnTheSearchPath;
    [Test] procedure ResolvesADottedUnitName;
    [Test] procedure MatchingIsCaseInsensitive;
    [Test] procedure UnknownUnitDoesNotResolve;
    [Test] procedure ResolvedUnitIsMarkedAsSource;

    // --- ordering ---
    [Test] procedure TheFirstSearchPathWins;
    [Test] procedure TheReferencingFilesFolderIsSearchedFirst;
    [Test] procedure AnExplicitInPathBeatsTheSearchPaths;

    // --- unit scope names ---
    [Test] procedure UnqualifiedNameResolvesThroughAUnitScope;
    [Test] procedure ResolvedNameIsTheQualifiedForm;
    [Test] procedure UnitScopesAreTriedInOrder;
    [Test] procedure TheUnqualifiedFileWinsOverAScopedOne;
    [Test] procedure PartiallyQualifiedNameResolvesThroughAUnitScope;
    [Test] procedure AlreadyQualifiedNamesDoNotGetAScopeApplied;
    [Test] procedure NamespacesAreParsedFromASemicolonList;
    [Test] procedure EmptyNamespaceEntriesAreIgnored;

    // --- dcu fallback ---
    [Test] procedure FallsBackToADcuWhenThereIsNoSource;
    [Test] procedure ADcuOnlyUnitIsNotMarkedAsSource;
    [Test] procedure SourceIsPreferredOverADcuInTheSameFolder;
    [Test] procedure SourceOnALaterPathBeatsADcuOnAnEarlierOne;

    // --- origins ---
    [Test] procedure OriginIsCarriedThroughFromTheSearchPath;
    [Test] procedure SearchPathsAreReportedInOrder;
    [Test] procedure AddingTheSamePathTwiceKeepsOnlyTheFirst;
  end;

implementation

uses
  System.IOUtils,
  System.SysUtils;

{ TUnitResolverTests }

procedure TUnitResolverTests.Setup;
begin
  FRoot := TPath.Combine(TPath.GetTempPath, 'dua-resolver-' + TGuid.NewGuid.ToString);
  TDirectory.CreateDirectory(FRoot);
  FResolver := TUnitResolver.Create;
end;

procedure TUnitResolverTests.TearDown;
begin
  FResolver := nil;
  if (FRoot <> '') and TDirectory.Exists(FRoot) then
    TDirectory.Delete(FRoot, true);
end;

procedure TUnitResolverTests.GivenFile(const relativePath : string);
var
  full : string;
begin
  full := TPath.Combine(FRoot, relativePath);
  TDirectory.CreateDirectory(ExtractFilePath(full));
  TFile.WriteAllText(full, 'unit placeholder;' + sLineBreak + 'interface' + sLineBreak + 'end.');
end;

function TUnitResolverTests.PathOf(const relativeFolder : string) : string;
begin
  result := TPath.Combine(FRoot, relativeFolder);
end;

function TUnitResolverTests.Resolve(const unitName : string) : TResolvedUnit;
begin
  result := ResolveFrom(unitName, '');
end;

function TUnitResolverTests.ResolveFrom(const unitName : string; const referencingFile : string) : TResolvedUnit;
begin
  if not FResolver.TryResolve(unitName, referencingFile, result) then
    Assert.Fail('could not resolve ' + unitName);
end;

function TUnitResolverTests.CanResolve(const unitName : string) : boolean;
var
  resolved : TResolvedUnit;
begin
  result := FResolver.TryResolve(unitName, '', resolved);
end;

procedure TUnitResolverTests.ResolvesAUnitOnTheSearchPath;
begin
  GivenFile('src\MyUnit.pas');
  FResolver.AddSearchPath(PathOf('src'), uoProject);

  Assert.AreEqual(TPath.Combine(PathOf('src'), 'MyUnit.pas'), Resolve('MyUnit').FileName);
end;

procedure TUnitResolverTests.ResolvesADottedUnitName;
begin
  GivenFile('src\My.Nested.Unit.pas');
  FResolver.AddSearchPath(PathOf('src'), uoProject);

  Assert.AreEqual(TPath.Combine(PathOf('src'), 'My.Nested.Unit.pas'), Resolve('My.Nested.Unit').FileName);
end;

procedure TUnitResolverTests.MatchingIsCaseInsensitive;
begin
  GivenFile('src\MyUnit.pas');
  FResolver.AddSearchPath(PathOf('src'), uoProject);

  Assert.IsTrue(CanResolve('myunit'));
  Assert.IsTrue(CanResolve('MYUNIT'));
end;

procedure TUnitResolverTests.UnknownUnitDoesNotResolve;
begin
  FResolver.AddSearchPath(PathOf('src'), uoProject);
  Assert.IsFalse(CanResolve('NoSuchUnit'));
end;

procedure TUnitResolverTests.ResolvedUnitIsMarkedAsSource;
begin
  GivenFile('src\MyUnit.pas');
  FResolver.AddSearchPath(PathOf('src'), uoProject);

  Assert.IsTrue(Resolve('MyUnit').IsSource);
end;

procedure TUnitResolverTests.TheFirstSearchPathWins;
begin
  GivenFile('first\MyUnit.pas');
  GivenFile('second\MyUnit.pas');
  FResolver.AddSearchPath(PathOf('first'), uoProject);
  FResolver.AddSearchPath(PathOf('second'), uoProject);

  Assert.AreEqual(TPath.Combine(PathOf('first'), 'MyUnit.pas'), Resolve('MyUnit').FileName);
end;

procedure TUnitResolverTests.TheReferencingFilesFolderIsSearchedFirst;
begin
  GivenFile('lib\MyUnit.pas');
  GivenFile('app\MyUnit.pas');
  GivenFile('app\Caller.pas');
  FResolver.AddSearchPath(PathOf('lib'), uoProject);

  Assert.AreEqual(TPath.Combine(PathOf('app'), 'MyUnit.pas'),
    ResolveFrom('MyUnit', TPath.Combine(PathOf('app'), 'Caller.pas')).FileName);
end;

procedure TUnitResolverTests.AnExplicitInPathBeatsTheSearchPaths;
begin
  GivenFile('lib\MyUnit.pas');
  GivenFile('elsewhere\MyUnit.pas');
  FResolver.AddSearchPath(PathOf('lib'), uoProject);
  FResolver.AddExplicitUnit('MyUnit', TPath.Combine(PathOf('elsewhere'), 'MyUnit.pas'));

  Assert.AreEqual(TPath.Combine(PathOf('elsewhere'), 'MyUnit.pas'), Resolve('MyUnit').FileName);
end;

procedure TUnitResolverTests.UnqualifiedNameResolvesThroughAUnitScope;
begin
  // this is what lets an old style `uses Classes` find System.Classes
  GivenFile('rtl\System.Classes.pas');
  FResolver.AddSearchPath(PathOf('rtl'), uoRTL);
  FResolver.AddNamespaces('System;Vcl');

  Assert.AreEqual(TPath.Combine(PathOf('rtl'), 'System.Classes.pas'), Resolve('Classes').FileName);
end;

procedure TUnitResolverTests.ResolvedNameIsTheQualifiedForm;
begin
  GivenFile('rtl\System.Classes.pas');
  FResolver.AddSearchPath(PathOf('rtl'), uoRTL);
  FResolver.AddNamespaces('System');

  Assert.AreEqual('System.Classes', Resolve('Classes').UnitName,
    'the graph should record the name the compiler resolves to');
end;

procedure TUnitResolverTests.UnitScopesAreTriedInOrder;
begin
  GivenFile('rtl\Vcl.Forms.pas');
  GivenFile('rtl\System.Forms.pas');
  FResolver.AddSearchPath(PathOf('rtl'), uoRTL);
  FResolver.AddNamespaces('System;Vcl');

  Assert.AreEqual('System.Forms', Resolve('Forms').UnitName, 'System comes first in the list');
end;

procedure TUnitResolverTests.TheUnqualifiedFileWinsOverAScopedOne;
begin
  GivenFile('src\Classes.pas');
  GivenFile('src\System.Classes.pas');
  FResolver.AddSearchPath(PathOf('src'), uoProject);
  FResolver.AddNamespaces('System');

  Assert.AreEqual('Classes', Resolve('Classes').UnitName,
    'the compiler tries the name as written before applying a scope');
end;

procedure TUnitResolverTests.PartiallyQualifiedNameResolvesThroughAUnitScope;
begin
  // `uses Generics.Defaults` is legal and common - the unit scope applies to a dotted
  // name just as much as to a bare one, so it finds System.Generics.Defaults
  GivenFile('rtl\System.Generics.Defaults.pas');
  FResolver.AddSearchPath(PathOf('rtl'), uoRTL);
  FResolver.AddNamespaces('System');

  Assert.AreEqual('System.Generics.Defaults', Resolve('Generics.Defaults').UnitName);
end;

procedure TUnitResolverTests.AlreadyQualifiedNamesDoNotGetAScopeApplied;
begin
  GivenFile('src\System.System.Classes.pas');
  GivenFile('src\System.Classes.pas');
  FResolver.AddSearchPath(PathOf('src'), uoProject);
  FResolver.AddNamespaces('System');

  Assert.AreEqual(TPath.Combine(PathOf('src'), 'System.Classes.pas'), Resolve('System.Classes').FileName);
end;

procedure TUnitResolverTests.NamespacesAreParsedFromASemicolonList;
begin
  FResolver.AddNamespaces('System;Vcl;Winapi');
  Assert.AreEqual<integer>(3, FResolver.Namespaces.Count);
  Assert.AreEqual('System', FResolver.Namespaces[0]);
  Assert.AreEqual('Winapi', FResolver.Namespaces[2]);
end;

procedure TUnitResolverTests.EmptyNamespaceEntriesAreIgnored;
begin
  // a dproj value that still has an unexpanded $(DCC_Namespace) leaves empty entries
  FResolver.AddNamespaces('System;;Vcl;');
  Assert.AreEqual<integer>(2, FResolver.Namespaces.Count);
end;

procedure TUnitResolverTests.FallsBackToADcuWhenThereIsNoSource;
begin
  GivenFile('lib\Precompiled.dcu');
  FResolver.AddSearchPath(PathOf('lib'), uoLibrary);

  Assert.AreEqual(TPath.Combine(PathOf('lib'), 'Precompiled.dcu'), Resolve('Precompiled').FileName);
end;

procedure TUnitResolverTests.ADcuOnlyUnitIsNotMarkedAsSource;
begin
  GivenFile('lib\Precompiled.dcu');
  FResolver.AddSearchPath(PathOf('lib'), uoLibrary);

  Assert.IsFalse(Resolve('Precompiled').IsSource, 'a dcu cannot be parsed for its uses clause');
end;

procedure TUnitResolverTests.SourceIsPreferredOverADcuInTheSameFolder;
begin
  GivenFile('lib\MyUnit.pas');
  GivenFile('lib\MyUnit.dcu');
  FResolver.AddSearchPath(PathOf('lib'), uoLibrary);

  Assert.AreEqual('.pas', ExtractFileExt(Resolve('MyUnit').FileName));
end;

procedure TUnitResolverTests.SourceOnALaterPathBeatsADcuOnAnEarlierOne;
begin
  GivenFile('first\MyUnit.dcu');
  GivenFile('second\MyUnit.pas');
  FResolver.AddSearchPath(PathOf('first'), uoLibrary);
  FResolver.AddSearchPath(PathOf('second'), uoProject);

  // a dcu is a dead end for the walk, so source anywhere is more useful
  Assert.AreEqual(TPath.Combine(PathOf('second'), 'MyUnit.pas'), Resolve('MyUnit').FileName);
end;

procedure TUnitResolverTests.OriginIsCarriedThroughFromTheSearchPath;
begin
  GivenFile('packages\FromPackage.pas');
  GivenFile('rtl\FromRtl.pas');
  FResolver.AddSearchPath(PathOf('packages'), uoPackage);
  FResolver.AddSearchPath(PathOf('rtl'), uoRTL);

  Assert.AreEqual(Ord(uoPackage), Ord(Resolve('FromPackage').Origin));
  Assert.AreEqual(Ord(uoRTL), Ord(Resolve('FromRtl').Origin));
end;

procedure TUnitResolverTests.SearchPathsAreReportedInOrder;
begin
  FResolver.AddSearchPath(PathOf('a'), uoProject);
  FResolver.AddSearchPath(PathOf('b'), uoLibrary);

  Assert.AreEqual<integer>(2, FResolver.SearchPaths.Count);
  Assert.AreEqual(PathOf('a'), FResolver.SearchPaths[0].Path);
  Assert.AreEqual(Ord(uoLibrary), Ord(FResolver.SearchPaths[1].Origin));
end;

procedure TUnitResolverTests.AddingTheSamePathTwiceKeepsOnlyTheFirst;
begin
  FResolver.AddSearchPath(PathOf('a'), uoProject);
  FResolver.AddSearchPath(PathOf('a'), uoLibrary);

  Assert.AreEqual<integer>(1, FResolver.SearchPaths.Count);
  Assert.AreEqual(Ord(uoProject), Ord(FResolver.SearchPaths[0].Origin),
    'the first origin should stick, as the earlier path is the one that wins');
end;

initialization
  TDUnitX.RegisterTestFixture(TUnitResolverTests);

end.
