unit DUA.Tests.Types;

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>
  ///   Kleene three valued logic. The interesting cases are the ones where unknown
  ///   collapses to a definite answer: false and unknown is false, true or unknown is
  ///   true. Those are what let us evaluate part of an expression we cannot fully
  ///   understand.
  /// </summary>
  [TestFixture]
  TTriStateTests = class
  public
    [Test]
    [TestCase('F and F', 'tsFalse,tsFalse,tsFalse')]
    [TestCase('F and T', 'tsFalse,tsTrue,tsFalse')]
    [TestCase('F and U', 'tsFalse,tsUnknown,tsFalse')]
    [TestCase('T and F', 'tsTrue,tsFalse,tsFalse')]
    [TestCase('T and T', 'tsTrue,tsTrue,tsTrue')]
    [TestCase('T and U', 'tsTrue,tsUnknown,tsUnknown')]
    [TestCase('U and F', 'tsUnknown,tsFalse,tsFalse')]
    [TestCase('U and T', 'tsUnknown,tsTrue,tsUnknown')]
    [TestCase('U and U', 'tsUnknown,tsUnknown,tsUnknown')]
    procedure AndFollowsKleeneLogic(const left : string; const right : string; const expected : string);

    [Test]
    [TestCase('F or F', 'tsFalse,tsFalse,tsFalse')]
    [TestCase('F or T', 'tsFalse,tsTrue,tsTrue')]
    [TestCase('F or U', 'tsFalse,tsUnknown,tsUnknown')]
    [TestCase('T or F', 'tsTrue,tsFalse,tsTrue')]
    [TestCase('T or T', 'tsTrue,tsTrue,tsTrue')]
    [TestCase('T or U', 'tsTrue,tsUnknown,tsTrue')]
    [TestCase('U or F', 'tsUnknown,tsFalse,tsUnknown')]
    [TestCase('U or T', 'tsUnknown,tsTrue,tsTrue')]
    [TestCase('U or U', 'tsUnknown,tsUnknown,tsUnknown')]
    procedure OrFollowsKleeneLogic(const left : string; const right : string; const expected : string);

    [Test]
    [TestCase('exact',          'Vcl.Forms|Vcl.Forms|True', '|')]
    [TestCase('exact wrong',    'Vcl.Forms|Vcl.Controls|False', '|')]
    [TestCase('case insensitive','vcl.forms|VCL.FORMS|True', '|')]
    [TestCase('no partial',     'Forms|Vcl.Forms|False', '|')]
    [TestCase('star all',       '*|Anything.At.All|True', '|')]
    [TestCase('prefix',         'Vcl.*|Vcl.Forms|True', '|')]
    [TestCase('prefix no',      'Vcl.*|System.Classes|False', '|')]
    [TestCase('prefix exact',   'Vcl.*|Vcl.|True', '|')]
    [TestCase('bare prefix',    'Vcl*|Vcl.Forms|True', '|')]
    [TestCase('suffix',         '*.Forms|Vcl.Forms|True', '|')]
    [TestCase('suffix no',      '*.Forms|Vcl.Formats|False', '|')]
    [TestCase('middle',         'Vcl.*Ctrls|Vcl.StdCtrls|True', '|')]
    [TestCase('middle no',      'Vcl.*Ctrls|Vcl.Graphics|False', '|')]
    [TestCase('two stars',      '*.Win.*|Data.Win.ADODB|True', '|')]
    [TestCase('question',       'Vcl.For?s|Vcl.Forms|True', '|')]
    [TestCase('question one',   'Vcl.For?|Vcl.Forms|False', '|')]
    [TestCase('star empty run', 'Vcl.*Forms|Vcl.Forms|True', '|')]
    [TestCase('empty pattern',  '|Vcl.Forms|False', '|')]
    [TestCase('star matches empty name', '*||True', '|')]
    procedure PatternMatchingFollowsGlobRules(const pattern : string; const value : string;
                                              const expected : boolean);

    [Test]
    [TestCase('plain',    'Vcl.Forms|False', '|')]
    [TestCase('star',     'Vcl.*|True', '|')]
    [TestCase('question', 'Vcl.For?s|True', '|')]
    [TestCase('empty',    '|False', '|')]
    procedure WildcardIsDetected(const pattern : string; const expected : boolean);

    [Test]
    [TestCase('not F', 'tsFalse,tsTrue')]
    [TestCase('not T', 'tsTrue,tsFalse')]
    [TestCase('not U', 'tsUnknown,tsUnknown')]
    procedure NotFollowsKleeneLogic(const value : string; const expected : string);
  end;

implementation

uses
  System.SysUtils,
  System.TypInfo,
  DUA.Types;

function ToTriState(const value : string) : TTriState;
begin
  result := TTriState(GetEnumValue(TypeInfo(TTriState), value));
end;

function TriStateName(const value : TTriState) : string;
begin
  result := GetEnumName(TypeInfo(TTriState), Ord(value));
end;

procedure TTriStateTests.AndFollowsKleeneLogic(const left : string; const right : string; const expected : string);
begin
  Assert.AreEqual(expected, TriStateName(TriStateAnd(ToTriState(left), ToTriState(right))));
end;

procedure TTriStateTests.OrFollowsKleeneLogic(const left : string; const right : string; const expected : string);
begin
  Assert.AreEqual(expected, TriStateName(TriStateOr(ToTriState(left), ToTriState(right))));
end;

procedure TTriStateTests.NotFollowsKleeneLogic(const value : string; const expected : string);
begin
  Assert.AreEqual(expected, TriStateName(TriStateNot(ToTriState(value))));
end;

procedure TTriStateTests.PatternMatchingFollowsGlobRules(const pattern : string;
  const value : string; const expected : boolean);
begin
  Assert.AreEqual(expected, MatchesUnitPattern(pattern, value),
    Format('%s against %s', [pattern, value]));
end;

procedure TTriStateTests.WildcardIsDetected(const pattern : string; const expected : boolean);
begin
  Assert.AreEqual(expected, IsWildcardPattern(pattern), pattern);
end;

initialization
  TDUnitX.RegisterTestFixture(TTriStateTests);

end.
