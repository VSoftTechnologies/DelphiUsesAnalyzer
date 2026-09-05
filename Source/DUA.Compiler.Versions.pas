unit DUA.Compiler.Versions;

interface

uses
  DUA.Defines;

type
  /// <summary>
  ///   The Delphi releases we can analyse. The tool itself is Delphi 13, but the project
  ///   being analysed may target anything, and every version dependent answer has to
  ///   describe the TARGET rather than the compiler that built this exe.
  /// </summary>
  TCompilerVersion = (
    cvUnknown,
    cvXE2, cvXE3, cvXE4, cvXE5, cvXE6, cvXE7, cvXE8,
    cvDelphi10_0, cvDelphi10_1, cvDelphi10_2, cvDelphi10_3, cvDelphi10_4,
    cvDelphi11, cvDelphi12, cvDelphi13
  );

  TDelphiPlatform = (
    dpUnknown,
    dpWin32, dpWin64, dpWin64x, dpWinArm64EC,
    dpOSX64, dpOSXArm64,
    dpAndroid, dpAndroid64,
    dpiOS64,
    dpLinux64
  );

  TCompilerVersions = record
  public
    /// <summary>Accepts "delphi13.0", "13", "13.0", "XE2" or "delphixe2".</summary>
    class function Parse(const value : string) : TCompilerVersion; static;
    class function ToDpmToken(const value : TCompilerVersion) : string; static;
    /// <summary>The registry and $(BDS) folder number, eg "37.0" for Delphi 13.</summary>
    class function ToBdsVersion(const value : TCompilerVersion) : string; static;
    /// <summary>The value {$IF CompilerVersion >= n} compares against.</summary>
    class function ToCompilerVersionNumber(const value : TCompilerVersion) : double; static;
    /// <summary>The VERnnn conditional symbol, eg "VER370".</summary>
    class function ToVersionDefine(const value : TCompilerVersion) : string; static;
    class function ToDisplayName(const value : TCompilerVersion) : string; static;

    /// <summary>
    ///   The Delphi release a dproj ProjectVersion indicates. Several values are shared
    ///   between an update of one release and the next release, so the answer is a best
    ///   guess - check IsAmbiguousProjectVersion and prefer an explicit compiler when it
    ///   says so.
    /// </summary>
    class function FromProjectVersion(const projectVersion : string) : TCompilerVersion; static;
    /// <summary>
    ///   True when more than one release writes this ProjectVersion, with a description
    ///   of the candidates suitable for a warning message.
    /// </summary>
    class function IsAmbiguousProjectVersion(const projectVersion : string;
                                             out candidates : string) : boolean; static;
  end;

  TDelphiPlatforms = record
  public
    class function Parse(const value : string) : TDelphiPlatform; static;
    class function ToName(const value : TDelphiPlatform) : string; static;
    class function IsWindows(const value : TDelphiPlatform) : boolean; static;
  end;

  TCompilerDefines = record
  public
    /// <summary>
    ///   Add the symbols the compiler predefines for this target. Deliberately does not
    ///   look at the host compiler's own conditionals - that is the trap that makes a
    ///   tool built with one Delphi give wrong answers about a project targeting another.
    /// </summary>
    class procedure Seed(const defines : IDefineSet; const compiler : TCompilerVersion;
                         const targetPlatform : TDelphiPlatform; const isConsole : boolean); static;
    /// <summary>The DCC_Namespace values the IDE supplies before the project adds its own.</summary>
    class function DefaultNamespaces(const targetPlatform : TDelphiPlatform) : string; static;
  end;

implementation

uses
  System.SysUtils;

{ TCompilerVersions }

class function TCompilerVersions.Parse(const value : string) : TCompilerVersion;
var
  normalised : string;
  compiler : TCompilerVersion;
begin
  normalised := LowerCase(Trim(value));
  if normalised = '' then
    Exit(cvUnknown);

  if normalised.StartsWith('delphi') then
    normalised := Copy(normalised, Length('delphi') + 1, MaxInt);

  for compiler := Succ(cvUnknown) to High(TCompilerVersion) do
  begin
    // 'delphi13.0' -> '13.0', and we also accept the bare major and the XE names
    if SameText(normalised, Copy(ToDpmToken(compiler), Length('delphi') + 1, MaxInt)) then
      Exit(compiler);
    if SameText(normalised + '.0', Copy(ToDpmToken(compiler), Length('delphi') + 1, MaxInt)) then
      Exit(compiler);
  end;

  result := cvUnknown;
end;

class function TCompilerVersions.ToDpmToken(const value : TCompilerVersion) : string;
begin
  case value of
    cvXE2 : result := 'delphixe2';
    cvXE3 : result := 'delphixe3';
    cvXE4 : result := 'delphixe4';
    cvXE5 : result := 'delphixe5';
    cvXE6 : result := 'delphixe6';
    cvXE7 : result := 'delphixe7';
    cvXE8 : result := 'delphixe8';
    cvDelphi10_0 : result := 'delphi10.0';
    cvDelphi10_1 : result := 'delphi10.1';
    cvDelphi10_2 : result := 'delphi10.2';
    cvDelphi10_3 : result := 'delphi10.3';
    cvDelphi10_4 : result := 'delphi10.4';
    cvDelphi11 : result := 'delphi11.0';
    cvDelphi12 : result := 'delphi12.0';
    cvDelphi13 : result := 'delphi13.0';
  else
    result := '';
  end;
end;

class function TCompilerVersions.ToBdsVersion(const value : TCompilerVersion) : string;
begin
  // Embarcadero skipped BDS 13.0 entirely - XE5 is 12.0 and XE6 is 14.0.
  case value of
    cvXE2 : result := '9.0';
    cvXE3 : result := '10.0';
    cvXE4 : result := '11.0';
    cvXE5 : result := '12.0';
    cvXE6 : result := '14.0';
    cvXE7 : result := '15.0';
    cvXE8 : result := '16.0';
    cvDelphi10_0 : result := '17.0';
    cvDelphi10_1 : result := '18.0';
    cvDelphi10_2 : result := '19.0';
    cvDelphi10_3 : result := '20.0';
    cvDelphi10_4 : result := '21.0';
    cvDelphi11 : result := '22.0';
    cvDelphi12 : result := '23.0';
    cvDelphi13 : result := '37.0';
  else
    result := '';
  end;
end;

class function TCompilerVersions.ToCompilerVersionNumber(const value : TCompilerVersion) : double;
begin
  case value of
    cvXE2 : result := 23;
    cvXE3 : result := 24;
    cvXE4 : result := 25;
    cvXE5 : result := 26;
    cvXE6 : result := 27;
    cvXE7 : result := 28;
    cvXE8 : result := 29;
    cvDelphi10_0 : result := 30;
    cvDelphi10_1 : result := 31;
    cvDelphi10_2 : result := 32;
    cvDelphi10_3 : result := 33;
    cvDelphi10_4 : result := 34;
    cvDelphi11 : result := 35;
    cvDelphi12 : result := 36;
    cvDelphi13 : result := 37;
  else
    result := 0;
  end;
end;

class function TCompilerVersions.ToVersionDefine(const value : TCompilerVersion) : string;
var
  number : double;
begin
  number := ToCompilerVersionNumber(value);
  if number = 0 then
    Exit('');
  result := Format('VER%d', [Round(number * 10)]);
end;

class function TCompilerVersions.ToDisplayName(const value : TCompilerVersion) : string;
begin
  case value of
    cvXE2 : result := 'Delphi XE2';
    cvXE3 : result := 'Delphi XE3';
    cvXE4 : result := 'Delphi XE4';
    cvXE5 : result := 'Delphi XE5';
    cvXE6 : result := 'Delphi XE6';
    cvXE7 : result := 'Delphi XE7';
    cvXE8 : result := 'Delphi XE8';
    cvDelphi10_0 : result := 'Delphi 10 Seattle';
    cvDelphi10_1 : result := 'Delphi 10.1 Berlin';
    cvDelphi10_2 : result := 'Delphi 10.2 Tokyo';
    cvDelphi10_3 : result := 'Delphi 10.3 Rio';
    cvDelphi10_4 : result := 'Delphi 10.4 Sydney';
    cvDelphi11 : result := 'Delphi 11 Alexandria';
    cvDelphi12 : result := 'Delphi 12 Athens';
    cvDelphi13 : result := 'Delphi 13 Florence';
  else
    result := 'unknown';
  end;
end;

function SplitProjectVersion(const projectVersion : string;
  out major : integer; out minor : integer) : boolean;
var
  dot : integer;
  text : string;
begin
  major := -1;
  minor := 0;
  text := Trim(projectVersion);
  if text = '' then
    Exit(false);

  dot := Pos('.', text);
  if dot > 0 then
  begin
    if not TryStrToInt(Copy(text, 1, dot - 1), major) then
      Exit(false);
    if not TryStrToInt(Copy(text, dot + 1, MaxInt), minor) then
      Exit(false);
  end
  else if not TryStrToInt(text, major) then
    Exit(false);

  result := true;
end;

class function TCompilerVersions.FromProjectVersion(const projectVersion : string) : TCompilerVersion;
var
  major : integer;
  minor : integer;
begin
  result := cvUnknown;
  if not SplitProjectVersion(projectVersion, major, minor) then
    Exit;

  case major of
    13 : result := cvXE2;
    14 :
      case minor of
        0..3 : result := cvXE3;
      else
        result := cvXE4;   // 14.4 is also XE3 Update 2 - see IsAmbiguousProjectVersion
      end;
    15 :
      case minor of
        0..3 : result := cvXE5;
      else
        result := cvXE6;
      end;
    16 : result := cvXE7;
    17 : result := cvXE8;
    18 :
      case minor of
        0..1 : result := cvDelphi10_0;
        2 : result := cvDelphi10_1;
        3..4 : result := cvDelphi10_2;
        5..8 : result := cvDelphi10_3;   // 18.8 is 10.3.3
      end;
    19 :
      case minor of
        0..2 : result := cvDelphi10_4;
      else
        result := cvDelphi11;            // .3 is 11.0, .4 is 11.1, .5 is 11.2/11.3
      end;
    20 :
      case minor of
        0..3 : result := cvDelphi12;
      else
        result := cvDelphi13;
      end;
  end;
end;

class function TCompilerVersions.IsAmbiguousProjectVersion(const projectVersion : string;
  out candidates : string) : boolean;
var
  major : integer;
  minor : integer;
begin
  candidates := '';
  result := false;
  if not SplitProjectVersion(projectVersion, major, minor) then
    Exit;

  // An IDE update often bumps ProjectVersion to the value the NEXT release also uses,
  // so these values genuinely cannot be told apart from the dproj alone.
  if (major = 14) and (minor = 4) then
    candidates := 'XE3 Update 2 / XE4'
  else if (major = 15) and (minor = 3) then
    candidates := 'XE5 / XE6'
  else if (major = 18) and (minor = 1) then
    candidates := '10.0 Update 1 / 10.1'
  else if (major = 18) and (minor = 2) then
    candidates := '10.1 Update 1 / 10.2'
  else if (major = 20) and (minor = 3) then
    candidates := '12.3 / 13.0';

  result := candidates <> '';
end;

{ TDelphiPlatforms }

class function TDelphiPlatforms.Parse(const value : string) : TDelphiPlatform;
var
  candidate : TDelphiPlatform;
begin
  for candidate := Succ(dpUnknown) to High(TDelphiPlatform) do
    if SameText(Trim(value), ToName(candidate)) then
      Exit(candidate);
  result := dpUnknown;
end;

class function TDelphiPlatforms.ToName(const value : TDelphiPlatform) : string;
begin
  case value of
    dpWin32 : result := 'Win32';
    dpWin64 : result := 'Win64';
    dpWin64x : result := 'Win64x';
    dpWinArm64EC : result := 'WinARM64EC';
    dpOSX64 : result := 'OSX64';
    dpOSXArm64 : result := 'OSXARM64';
    dpAndroid : result := 'Android';
    dpAndroid64 : result := 'Android64';
    dpiOS64 : result := 'iOSDevice64';
    dpLinux64 : result := 'Linux64';
  else
    result := '';
  end;
end;

class function TDelphiPlatforms.IsWindows(const value : TDelphiPlatform) : boolean;
begin
  result := value in [dpWin32, dpWin64, dpWin64x, dpWinArm64EC];
end;

{ TCompilerDefines }

class procedure TCompilerDefines.Seed(const defines : IDefineSet; const compiler : TCompilerVersion;
  const targetPlatform : TDelphiPlatform; const isConsole : boolean);
var
  versionNumber : double;
begin
  versionNumber := TCompilerVersions.ToCompilerVersionNumber(compiler);
  if versionNumber > 0 then
  begin
    defines.Define(TCompilerVersions.ToVersionDefine(compiler));
    defines.SetNumeric('CompilerVersion', versionNumber);
    defines.SetNumeric('RTLVersion', versionNumber);
  end;

  defines.Define('CONDITIONALEXPRESSIONS');
  defines.Define('UNICODE');
  defines.Define('ASSEMBLER');
  defines.Define('NATIVECODE');

  if compiler >= cvDelphi10_4 then
    defines.Define('MANAGED_RECORD');

  case targetPlatform of
    dpWin32 :
      begin
        defines.Define('MSWINDOWS');
        defines.Define('WIN32');
        defines.Define('CPU386');
        defines.Define('CPUX86');
        defines.Define('CPU32BITS');
      end;
    dpWin64, dpWin64x :
      begin
        defines.Define('MSWINDOWS');
        defines.Define('WIN64');
        defines.Define('CPUX64');
        defines.Define('CPU64BITS');
      end;
    dpWinArm64EC :
      begin
        defines.Define('MSWINDOWS');
        defines.Define('WIN64');
        defines.Define('CPUARM64');
        defines.Define('CPUARM');
        defines.Define('CPU64BITS');
      end;
    dpLinux64 :
      begin
        defines.Define('LINUX');
        defines.Define('LINUX64');
        defines.Define('POSIX');
        defines.Define('POSIX64');
        defines.Define('CPUX64');
        defines.Define('CPU64BITS');
        defines.Define('EXTERNALLINKER');
      end;
    dpOSX64 :
      begin
        defines.Define('MACOS');
        defines.Define('MACOS64');
        defines.Define('POSIX');
        defines.Define('POSIX64');
        defines.Define('CPUX64');
        defines.Define('CPU64BITS');
        defines.Define('EXTERNALLINKER');
      end;
    dpOSXArm64 :
      begin
        defines.Define('MACOS');
        defines.Define('MACOS64');
        defines.Define('POSIX');
        defines.Define('POSIX64');
        defines.Define('CPUARM64');
        defines.Define('CPUARM');
        defines.Define('CPU64BITS');
        defines.Define('EXTERNALLINKER');
      end;
    dpAndroid :
      begin
        defines.Define('ANDROID');
        defines.Define('ANDROID32');
        defines.Define('POSIX');
        defines.Define('CPUARM');
        defines.Define('CPUARM32');
        defines.Define('CPU32BITS');
        defines.Define('EXTERNALLINKER');
      end;
    dpAndroid64 :
      begin
        defines.Define('ANDROID');
        defines.Define('ANDROID64');
        defines.Define('POSIX');
        defines.Define('POSIX64');
        defines.Define('CPUARM64');
        defines.Define('CPUARM');
        defines.Define('CPU64BITS');
        defines.Define('EXTERNALLINKER');
      end;
    dpiOS64 :
      begin
        defines.Define('IOS');
        defines.Define('IOS64');
        defines.Define('MACOS');
        defines.Define('POSIX');
        defines.Define('POSIX64');
        defines.Define('CPUARM64');
        defines.Define('CPUARM');
        defines.Define('CPU64BITS');
        defines.Define('EXTERNALLINKER');
      end;
  end;

  if isConsole then
    defines.Define('CONSOLE');
end;

class function TCompilerDefines.DefaultNamespaces(const targetPlatform : TDelphiPlatform) : string;
const
  cBase = 'System;Xml;Data;Datasnap;Web;Soap';
  cWindowsCommon = 'Winapi;System.Win;Data.Win;Datasnap.Win;Web.Win;Soap.Win;Xml.Win';
begin
  case targetPlatform of
    // there is no 64 bit BDE, which is the only difference between the two lists
    dpWin32 : result := cWindowsCommon + ';Bde;' + cBase;
    dpWin64, dpWin64x, dpWinArm64EC : result := cWindowsCommon + ';' + cBase;
    dpOSX64, dpOSXArm64, dpiOS64 : result := 'Macapi;Posix;' + cBase;
    dpAndroid, dpAndroid64 : result := 'Androidapi;Posix;' + cBase;
    dpLinux64 : result := 'Posix;' + cBase;
  else
    result := cBase;
  end;
end;

end.
