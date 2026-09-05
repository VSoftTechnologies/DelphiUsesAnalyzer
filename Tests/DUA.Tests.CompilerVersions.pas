unit DUA.Tests.CompilerVersions;

interface

uses
  DUnitX.TestFramework,
  DUA.Defines,
  DUA.Compiler.Versions;

type
  [TestFixture]
  TCompilerVersionTests = class
  public
    [Test]
    [TestCase('canonical', 'delphi13.0,cvDelphi13')]
    [TestCase('major only', '13,cvDelphi13')]
    [TestCase('dotted',     '13.0,cvDelphi13')]
    [TestCase('delphi 12',  'delphi12.0,cvDelphi12')]
    [TestCase('xe2 name',   'XE2,cvXE2')]
    [TestCase('xe2 token',  'delphixe2,cvXE2')]
    [TestCase('10.4',       '10.4,cvDelphi10_4')]
    [TestCase('nonsense',   'banana,cvUnknown')]
    [TestCase('empty',      ',cvUnknown')]
    procedure ParsesCompilerTokens(const value : string; const expected : string);

    [Test]
    [TestCase('13',   'cvDelphi13,delphi13.0')]
    [TestCase('12',   'cvDelphi12,delphi12.0')]
    [TestCase('10.4', 'cvDelphi10_4,delphi10.4')]
    [TestCase('xe2',  'cvXE2,delphixe2')]
    procedure FormatsCompilerTokens(const value : string; const expected : string);

    [Test]
    [TestCase('13',   'cvDelphi13,37.0')]
    [TestCase('12',   'cvDelphi12,23.0')]
    [TestCase('11',   'cvDelphi11,22.0')]
    [TestCase('10.4', 'cvDelphi10_4,21.0')]
    [TestCase('10.0', 'cvDelphi10_0,17.0')]
    [TestCase('xe7',  'cvXE7,15.0')]
    [TestCase('xe6',  'cvXE6,14.0')]
    [TestCase('xe5',  'cvXE5,12.0')]
    [TestCase('xe2',  'cvXE2,9.0')]
    procedure MapsToBdsVersion(const value : string; const expected : string);

    [Test]
    procedure ThereIsNoBdsVersionThirteen;

    [Test]
    [TestCase('13',   'cvDelphi13,37')]
    [TestCase('12',   'cvDelphi12,36')]
    [TestCase('11',   'cvDelphi11,35')]
    [TestCase('10.4', 'cvDelphi10_4,34')]
    [TestCase('xe2',  'cvXE2,23')]
    procedure MapsToCompilerVersionNumber(const value : string; const expected : integer);

    [Test]
    [TestCase('13',  'cvDelphi13,VER370')]
    [TestCase('12',  'cvDelphi12,VER360')]
    [TestCase('xe2', 'cvXE2,VER230')]
    procedure MapsToVersionDefine(const value : string; const expected : string);

    [Test]
    [TestCase('13',    '20.4,cvDelphi13')]
    [TestCase('12',    '20.3,cvDelphi12')]
    [TestCase('12 ga', '20.0,cvDelphi12')]
    [TestCase('11.2',  '19.5,cvDelphi11')]
    [TestCase('11.0',  '19.3,cvDelphi11')]
    [TestCase('10.4',  '19.2,cvDelphi10_4')]
    [TestCase('10.3.3','18.8,cvDelphi10_3')]
    [TestCase('10.2',  '18.4,cvDelphi10_2')]
    [TestCase('10.1',  '18.2,cvDelphi10_1')]
    [TestCase('10.0',  '18.0,cvDelphi10_0')]
    [TestCase('xe8',   '17.2,cvXE8')]
    [TestCase('xe7',   '16.1,cvXE7')]
    [TestCase('xe6',   '15.4,cvXE6')]
    [TestCase('xe5',   '15.3,cvXE5')]
    [TestCase('xe4',   '14.4,cvXE4')]
    [TestCase('xe3',   '14.3,cvXE3')]
    [TestCase('xe2',   '13.4,cvXE2')]
    [TestCase('nonsense','banana,cvUnknown')]
    [TestCase('empty',   ',cvUnknown')]
    procedure MapsProjectVersionToACompiler(const value : string; const expected : string);

    [Test]
    [TestCase('xe3u2 or xe4',  '14.4,XE3 Update 2 / XE4')]
    [TestCase('xe5 or xe6',    '15.3,XE5 / XE6')]
    [TestCase('10.0u1 or 10.1','18.1,10.0 Update 1 / 10.1')]
    [TestCase('10.1u1 or 10.2','18.2,10.1 Update 1 / 10.2')]
    [TestCase('12.3 or 13',    '20.3,12.3 / 13.0')]
    procedure AmbiguousProjectVersionsNameTheirCandidates(const value : string; const expected : string);

    [Test]
    [TestCase('13',  '20.4')]
    [TestCase('11',  '19.5')]
    [TestCase('xe2', '13.4')]
    procedure UnambiguousProjectVersionsAreNotFlagged(const value : string);
  end;

  [TestFixture]
  TPlatformTests = class
  public
    [Test]
    [TestCase('win32',    'Win32,dpWin32')]
    [TestCase('lowercase','win32,dpWin32')]
    [TestCase('win64',    'Win64,dpWin64')]
    [TestCase('win64x',   'Win64x,dpWin64x')]
    [TestCase('arm64ec',  'WinARM64EC,dpWinArm64EC')]
    [TestCase('linux',    'Linux64,dpLinux64')]
    [TestCase('osxarm',   'OSXARM64,dpOSXArm64')]
    [TestCase('nonsense', 'banana,dpUnknown')]
    procedure ParsesPlatformNames(const value : string; const expected : string);

    [Test]
    [TestCase('win32', 'dpWin32,Win32')]
    [TestCase('win64', 'dpWin64,Win64')]
    [TestCase('linux', 'dpLinux64,Linux64')]
    procedure FormatsPlatformNames(const value : string; const expected : string);
  end;

  [TestFixture]
  TCompilerDefineTests = class
  private
    FDefines : IDefineSet;
    procedure SeedFor(const platformName : string; const isConsole : boolean = true);
  public
    [Setup]
    procedure Setup;

    [Test] procedure SeedsTheVersionDefineForTheTargetCompiler;
    [Test] procedure SeedsCompilerVersionAsANumberForTheTargetNotTheHost;
    [Test] procedure SeedsRtlVersionAsANumber;
    [Test] procedure SeedsConditionalExpressionsAndUnicode;

    [Test] procedure Win32SeedsWindowsAndThirtyTwoBitSymbols;
    [Test] procedure Win64SeedsWindowsAndSixtyFourBitSymbols;
    [Test] procedure Win32DoesNotSeedWin64;
    [Test] procedure Linux64SeedsPosixNotWindows;

    [Test] procedure ConsoleAppSeedsConsole;
    [Test] procedure NonConsoleAppDoesNotSeedConsole;

    [Test] procedure Win32DefaultNamespacesIncludeBde;
    [Test] procedure Win64DefaultNamespacesDoNotIncludeBde;
    [Test] procedure DefaultNamespacesIncludeTheCommonScopes;
  end;

implementation

uses
  System.SysUtils,
  System.TypInfo;

function ToCompiler(const value : string) : TCompilerVersion;
begin
  result := TCompilerVersion(GetEnumValue(TypeInfo(TCompilerVersion), value));
end;

function CompilerName(const value : TCompilerVersion) : string;
begin
  result := GetEnumName(TypeInfo(TCompilerVersion), Ord(value));
end;

function ToPlatform(const value : string) : TDelphiPlatform;
begin
  result := TDelphiPlatform(GetEnumValue(TypeInfo(TDelphiPlatform), value));
end;

function PlatformName(const value : TDelphiPlatform) : string;
begin
  result := GetEnumName(TypeInfo(TDelphiPlatform), Ord(value));
end;

{ TCompilerVersionTests }

procedure TCompilerVersionTests.ParsesCompilerTokens(const value : string; const expected : string);
begin
  Assert.AreEqual(expected, CompilerName(TCompilerVersions.Parse(value)), 'parsing: ' + value);
end;

procedure TCompilerVersionTests.FormatsCompilerTokens(const value : string; const expected : string);
begin
  Assert.AreEqual(expected, TCompilerVersions.ToDpmToken(ToCompiler(value)));
end;

procedure TCompilerVersionTests.MapsToBdsVersion(const value : string; const expected : string);
begin
  Assert.AreEqual(expected, TCompilerVersions.ToBdsVersion(ToCompiler(value)));
end;

procedure TCompilerVersionTests.ThereIsNoBdsVersionThirteen;
var
  compiler : TCompilerVersion;
begin
  // Embarcadero skipped 13.0 - XE5 is 12.0 and XE6 is 14.0. Getting this wrong means
  // reading the wrong registry key and finding no Delphi at all.
  for compiler := Low(TCompilerVersion) to High(TCompilerVersion) do
    Assert.AreNotEqual('13.0', TCompilerVersions.ToBdsVersion(compiler),
      CompilerName(compiler) + ' claims to be BDS 13.0');
end;

procedure TCompilerVersionTests.MapsToCompilerVersionNumber(const value : string; const expected : integer);
begin
  Assert.AreEqual(double(expected), TCompilerVersions.ToCompilerVersionNumber(ToCompiler(value)), 0.001);
end;

procedure TCompilerVersionTests.MapsToVersionDefine(const value : string; const expected : string);
begin
  Assert.AreEqual(expected, TCompilerVersions.ToVersionDefine(ToCompiler(value)));
end;

procedure TCompilerVersionTests.MapsProjectVersionToACompiler(const value : string; const expected : string);
begin
  Assert.AreEqual(expected, CompilerName(TCompilerVersions.FromProjectVersion(value)),
    'project version: ' + value);
end;

procedure TCompilerVersionTests.AmbiguousProjectVersionsNameTheirCandidates(const value : string; const expected : string);
var
  candidates : string;
begin
  // An IDE update often adopts the ProjectVersion the next release also uses, so these
  // cannot be told apart from the dproj alone and the user has to say which they meant.
  Assert.IsTrue(TCompilerVersions.IsAmbiguousProjectVersion(value, candidates),
    value + ' should be ambiguous');
  Assert.AreEqual(expected, candidates);
end;

procedure TCompilerVersionTests.UnambiguousProjectVersionsAreNotFlagged(const value : string);
var
  candidates : string;
begin
  Assert.IsFalse(TCompilerVersions.IsAmbiguousProjectVersion(value, candidates),
    value + ' should not be ambiguous');
  Assert.AreEqual('', candidates);
end;

{ TPlatformTests }

procedure TPlatformTests.ParsesPlatformNames(const value : string; const expected : string);
begin
  Assert.AreEqual(expected, PlatformName(TDelphiPlatforms.Parse(value)), 'parsing: ' + value);
end;

procedure TPlatformTests.FormatsPlatformNames(const value : string; const expected : string);
begin
  Assert.AreEqual(expected, TDelphiPlatforms.ToName(ToPlatform(value)));
end;

{ TCompilerDefineTests }

procedure TCompilerDefineTests.Setup;
begin
  FDefines := TDefineSet.Create;
end;

procedure TCompilerDefineTests.SeedFor(const platformName : string; const isConsole : boolean);
begin
  TCompilerDefines.Seed(FDefines, cvDelphi13, TDelphiPlatforms.Parse(platformName), isConsole);
end;

procedure TCompilerDefineTests.SeedsTheVersionDefineForTheTargetCompiler;
begin
  SeedFor('Win32');
  Assert.IsTrue(FDefines.IsDefined('VER370'));
end;

procedure TCompilerDefineTests.SeedsCompilerVersionAsANumberForTheTargetNotTheHost;
var
  value : double;
begin
  TCompilerDefines.Seed(FDefines, cvDelphi11, dpWin32, true);

  Assert.IsTrue(FDefines.TryGetNumeric('CompilerVersion', value));
  Assert.AreEqual(35.0, value, 0.001, 'CompilerVersion must describe the analysed project');
end;

procedure TCompilerDefineTests.SeedsRtlVersionAsANumber;
var
  value : double;
begin
  SeedFor('Win32');
  Assert.IsTrue(FDefines.TryGetNumeric('RTLVersion', value));
  Assert.AreEqual(37.0, value, 0.001);
end;

procedure TCompilerDefineTests.SeedsConditionalExpressionsAndUnicode;
begin
  SeedFor('Win32');
  Assert.IsTrue(FDefines.IsDefined('CONDITIONALEXPRESSIONS'));
  Assert.IsTrue(FDefines.IsDefined('UNICODE'));
end;

procedure TCompilerDefineTests.Win32SeedsWindowsAndThirtyTwoBitSymbols;
begin
  SeedFor('Win32');
  Assert.IsTrue(FDefines.IsDefined('MSWINDOWS'), 'MSWINDOWS');
  Assert.IsTrue(FDefines.IsDefined('WIN32'), 'WIN32');
  Assert.IsTrue(FDefines.IsDefined('CPUX86'), 'CPUX86');
  Assert.IsTrue(FDefines.IsDefined('CPU32BITS'), 'CPU32BITS');
end;

procedure TCompilerDefineTests.Win64SeedsWindowsAndSixtyFourBitSymbols;
begin
  SeedFor('Win64');
  Assert.IsTrue(FDefines.IsDefined('MSWINDOWS'), 'MSWINDOWS');
  Assert.IsTrue(FDefines.IsDefined('WIN64'), 'WIN64');
  Assert.IsTrue(FDefines.IsDefined('CPUX64'), 'CPUX64');
  Assert.IsTrue(FDefines.IsDefined('CPU64BITS'), 'CPU64BITS');
end;

procedure TCompilerDefineTests.Win32DoesNotSeedWin64;
begin
  SeedFor('Win32');
  Assert.IsFalse(FDefines.IsDefined('WIN64'));
  Assert.IsFalse(FDefines.IsDefined('CPUX64'));
end;

procedure TCompilerDefineTests.Linux64SeedsPosixNotWindows;
begin
  SeedFor('Linux64');
  Assert.IsTrue(FDefines.IsDefined('LINUX'), 'LINUX');
  Assert.IsTrue(FDefines.IsDefined('LINUX64'), 'LINUX64');
  Assert.IsTrue(FDefines.IsDefined('POSIX'), 'POSIX');
  Assert.IsFalse(FDefines.IsDefined('MSWINDOWS'), 'MSWINDOWS must not be defined for linux');
end;

procedure TCompilerDefineTests.ConsoleAppSeedsConsole;
begin
  SeedFor('Win32', true);
  Assert.IsTrue(FDefines.IsDefined('CONSOLE'));
end;

procedure TCompilerDefineTests.NonConsoleAppDoesNotSeedConsole;
begin
  SeedFor('Win32', false);
  Assert.IsFalse(FDefines.IsDefined('CONSOLE'));
end;

procedure TCompilerDefineTests.Win32DefaultNamespacesIncludeBde;
begin
  // there is no 64 bit BDE, which is why the win32 and win64 lists differ
  Assert.Contains(TCompilerDefines.DefaultNamespaces(dpWin32), 'Bde');
end;

procedure TCompilerDefineTests.Win64DefaultNamespacesDoNotIncludeBde;
begin
  Assert.DoesNotContain(TCompilerDefines.DefaultNamespaces(dpWin64), 'Bde');
end;

procedure TCompilerDefineTests.DefaultNamespacesIncludeTheCommonScopes;
var
  namespaces : string;
begin
  namespaces := TCompilerDefines.DefaultNamespaces(dpWin32);
  Assert.Contains(namespaces, 'System');
  Assert.Contains(namespaces, 'Winapi');
  Assert.Contains(namespaces, 'Data');
end;

initialization
  TDUnitX.RegisterTestFixture(TCompilerVersionTests);
  TDUnitX.RegisterTestFixture(TPlatformTests);
  TDUnitX.RegisterTestFixture(TCompilerDefineTests);

end.
