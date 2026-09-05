unit DUA.Defines;

interface

uses
  Spring.Collections;

type
  /// <summary>
  ///   The set of conditional symbols in effect while scanning. Delphi symbols are
  ///   case insensitive. Numeric symbols (CompilerVersion, RTLVersion) are held
  ///   separately because {$IF CompilerVersion >= 36} compares them as numbers - they
  ///   are not "defined" in the {$IFDEF} sense.
  /// </summary>
  IDefineSet = interface
    ['{4A0A9A2E-6C3E-4E7B-9A2E-5D2F3B9E1C40}']
    procedure Define(const name : string);
    procedure Undefine(const name : string);
    function IsDefined(const name : string) : boolean;

    procedure SetNumeric(const name : string; const value : double);
    function TryGetNumeric(const name : string; out value : double) : boolean;

    /// <summary>Defined symbols, uppercased and sorted, for reporting.</summary>
    function ToArray : TArray<string>;
    function Clone : IDefineSet;
  end;

  TDefineSet = class(TInterfacedObject, IDefineSet)
  private
    // Symbols are stored uppercased, which is how we get case insensitivity.
    FDefines : ISet<string>;
    FNumerics : IDictionary<string, double>;
  protected
    procedure Define(const name : string);
    procedure Undefine(const name : string);
    function IsDefined(const name : string) : boolean;
    procedure SetNumeric(const name : string; const value : double);
    function TryGetNumeric(const name : string; out value : double) : boolean;
    function ToArray : TArray<string>;
    function Clone : IDefineSet;
  public
    constructor Create;
  end;

implementation

uses
  System.Generics.Collections,
  System.Generics.Defaults,
  System.SysUtils;

constructor TDefineSet.Create;
begin
  inherited Create;
  FDefines := TCollections.CreateSet<string>;
  FNumerics := TCollections.CreateDictionary<string, double>;
end;

procedure TDefineSet.Define(const name : string);
begin
  if name <> '' then
    FDefines.Add(UpperCase(name));
end;

procedure TDefineSet.Undefine(const name : string);
begin
  FDefines.Remove(UpperCase(name));
end;

function TDefineSet.IsDefined(const name : string) : boolean;
begin
  result := FDefines.Contains(UpperCase(name));
end;

procedure TDefineSet.SetNumeric(const name : string; const value : double);
begin
  FNumerics[UpperCase(name)] := value;
end;

function TDefineSet.TryGetNumeric(const name : string; out value : double) : boolean;
begin
  result := FNumerics.TryGetValue(UpperCase(name), value);
  if not result then
    value := 0;
end;

function TDefineSet.ToArray : TArray<string>;
begin
  result := FDefines.ToArray;
  System.Generics.Collections.TArray.Sort<string>(result, TStringComparer.Ordinal);
end;

function TDefineSet.Clone : IDefineSet;
var
  clone : TDefineSet;
  name : string;
begin
  clone := TDefineSet.Create;
  result := clone;
  for name in FDefines do
    clone.FDefines.Add(name);
  for name in FNumerics.Keys do
    clone.FNumerics[name] := FNumerics[name];
end;

end.
