unit DUA.Tests.Defines;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDefineSetTests = class
  public
    [Test]
    procedure NewSetHasNothingDefined;

    [Test]
    procedure DefineMakesSymbolDefined;

    [Test]
    [TestCase('lower asked upper', 'mswindows,MSWINDOWS')]
    [TestCase('upper asked lower', 'MSWINDOWS,mswindows')]
    [TestCase('mixed case',        'MsWindows,mSwINDOWS')]
    procedure IsDefinedIsCaseInsensitive(const defined : string; const asked : string);

    [Test]
    procedure UndefineRemovesSymbol;

    [Test]
    procedure UndefineIsCaseInsensitive;

    [Test]
    procedure UndefiningAnUndefinedSymbolIsHarmless;

    [Test]
    procedure DefiningTwiceThenUndefiningOnceLeavesItUndefined;

    [Test]
    procedure ToArrayReturnsDefinedSymbolsSorted;

    [Test]
    procedure ToArrayOfEmptySetIsEmpty;

    [Test]
    procedure NumericSymbolCanBeReadBack;

    [Test]
    procedure TryGetNumericIsFalseForUnknownSymbol;

    [Test]
    procedure TryGetNumericIsCaseInsensitive;

    [Test]
    procedure NumericSymbolIsNotAlsoDefined;

    [Test]
    procedure CloneCarriesDefinesAndNumerics;

    [Test]
    procedure ChangingACloneDoesNotAffectTheOriginal;
  end;

implementation

uses
  System.SysUtils,
  DUA.Defines;

procedure TDefineSetTests.NewSetHasNothingDefined;
var
  defines : IDefineSet;
begin
  defines := TDefineSet.Create;
  Assert.IsFalse(defines.IsDefined('MSWINDOWS'));
end;

procedure TDefineSetTests.DefineMakesSymbolDefined;
var
  defines : IDefineSet;
begin
  defines := TDefineSet.Create;
  defines.Define('MSWINDOWS');
  Assert.IsTrue(defines.IsDefined('MSWINDOWS'));
end;

procedure TDefineSetTests.IsDefinedIsCaseInsensitive(const defined : string; const asked : string);
var
  defines : IDefineSet;
begin
  defines := TDefineSet.Create;
  defines.Define(defined);
  Assert.IsTrue(defines.IsDefined(asked));
end;

procedure TDefineSetTests.UndefineRemovesSymbol;
var
  defines : IDefineSet;
begin
  defines := TDefineSet.Create;
  defines.Define('DEBUG');
  defines.Undefine('DEBUG');
  Assert.IsFalse(defines.IsDefined('DEBUG'));
end;

procedure TDefineSetTests.UndefineIsCaseInsensitive;
var
  defines : IDefineSet;
begin
  defines := TDefineSet.Create;
  defines.Define('DEBUG');
  defines.Undefine('debug');
  Assert.IsFalse(defines.IsDefined('DEBUG'));
end;

procedure TDefineSetTests.UndefiningAnUndefinedSymbolIsHarmless;
var
  defines : IDefineSet;
begin
  defines := TDefineSet.Create;
  defines.Undefine('NEVER_DEFINED');
  Assert.IsFalse(defines.IsDefined('NEVER_DEFINED'));
end;

procedure TDefineSetTests.DefiningTwiceThenUndefiningOnceLeavesItUndefined;
var
  defines : IDefineSet;
begin
  defines := TDefineSet.Create;
  defines.Define('DEBUG');
  defines.Define('DEBUG');
  defines.Undefine('DEBUG');
  Assert.IsFalse(defines.IsDefined('DEBUG'), 'defines are a set, not a counter');
end;

procedure TDefineSetTests.ToArrayReturnsDefinedSymbolsSorted;
var
  defines : IDefineSet;
  symbols : TArray<string>;
begin
  defines := TDefineSet.Create;
  defines.Define('WIN32');
  defines.Define('CONSOLE');
  defines.Define('MSWINDOWS');

  symbols := defines.ToArray;

  Assert.AreEqual<integer>(3, Length(symbols));
  Assert.AreEqual('CONSOLE', symbols[0]);
  Assert.AreEqual('MSWINDOWS', symbols[1]);
  Assert.AreEqual('WIN32', symbols[2]);
end;

procedure TDefineSetTests.ToArrayOfEmptySetIsEmpty;
var
  defines : IDefineSet;
begin
  defines := TDefineSet.Create;
  Assert.AreEqual<integer>(0, Length(defines.ToArray));
end;

procedure TDefineSetTests.NumericSymbolCanBeReadBack;
var
  defines : IDefineSet;
  value : double;
begin
  defines := TDefineSet.Create;
  defines.SetNumeric('CompilerVersion', 37.0);

  Assert.IsTrue(defines.TryGetNumeric('CompilerVersion', value));
  Assert.AreEqual(37.0, value, 0.0001);
end;

procedure TDefineSetTests.TryGetNumericIsFalseForUnknownSymbol;
var
  defines : IDefineSet;
  value : double;
begin
  defines := TDefineSet.Create;
  Assert.IsFalse(defines.TryGetNumeric('NoSuchSymbol', value));
end;

procedure TDefineSetTests.TryGetNumericIsCaseInsensitive;
var
  defines : IDefineSet;
  value : double;
begin
  defines := TDefineSet.Create;
  defines.SetNumeric('CompilerVersion', 37.0);

  Assert.IsTrue(defines.TryGetNumeric('COMPILERVERSION', value));
  Assert.AreEqual(37.0, value, 0.0001);
end;

procedure TDefineSetTests.NumericSymbolIsNotAlsoDefined;
var
  defines : IDefineSet;
begin
  defines := TDefineSet.Create;
  defines.SetNumeric('CompilerVersion', 37.0);
  Assert.IsFalse(defines.IsDefined('CompilerVersion'),
    'CompilerVersion has a value but is not a {$IFDEF} symbol');
end;

procedure TDefineSetTests.CloneCarriesDefinesAndNumerics;
var
  defines : IDefineSet;
  clone : IDefineSet;
  value : double;
begin
  defines := TDefineSet.Create;
  defines.Define('MSWINDOWS');
  defines.SetNumeric('CompilerVersion', 37.0);

  clone := defines.Clone;

  Assert.IsTrue(clone.IsDefined('MSWINDOWS'));
  Assert.IsTrue(clone.TryGetNumeric('CompilerVersion', value));
  Assert.AreEqual(37.0, value, 0.0001);
end;

procedure TDefineSetTests.ChangingACloneDoesNotAffectTheOriginal;
var
  defines : IDefineSet;
  clone : IDefineSet;
begin
  defines := TDefineSet.Create;
  defines.Define('MSWINDOWS');

  clone := defines.Clone;
  clone.Undefine('MSWINDOWS');
  clone.Define('LINUX');

  Assert.IsTrue(defines.IsDefined('MSWINDOWS'), 'original lost a define');
  Assert.IsFalse(defines.IsDefined('LINUX'), 'original gained a define');
end;

initialization
  TDUnitX.RegisterTestFixture(TDefineSetTests);

end.
