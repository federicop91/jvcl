unit MainCtrl;

interface

uses
  Classes, ParserTypes, Settings;

const
  CSummaryDescription = 'Summary'#13#10'  Write here a summary (1 line)';
  CSummaryDescriptionOverride = CSummaryDescription +
    #13#10'  This is an overridden method, you don''t have to describe these' +
    #13#10'  if it does the same as the inherited method';
  CDescriptionDescription = 'Description'#13#10'  Write here a description'#13#10;
  CSeeAlsoDescription = 'See Also'#13#10'  List here other properties, methods (comma seperated)'#13#10 +
    '  Remove the ''See Also'' section if there are no references';
  CReturnsDescription = 'Return value'#13#10'  Describe here what the function returns';
  CParamDescription = 'Parameters'#13#10;
  CValueReference = '(Value = %Value - for reference)';
  CClassInfo = '<TITLEIMG %s>'#13#10'JVCLInfo'#13#10'  GROUP=JVCL.??'#13#10'  FLAG=Component'#13#10;

type
  TMainCtrl = class
  private
    FSkipList: TStrings;
    FParsedOK: Integer;
    FParsedError: Integer;
    FProcessList: TStrings;
    FMessagesList: TStrings;

    FShowOtherFiles: Boolean;
    FShowIgnoredFiles: Boolean;
    FShowCompletedFiles: Boolean;
    FShowGeneratedFiles: Boolean;

    FAllFiles: TStringList;
    FAllFilteredFiles: TStringList;

    procedure SetShowCompletedFiles(const Value: Boolean);
    procedure SetShowIgnoredFiles(const Value: Boolean);
    procedure SetShowOtherFiles(const Value: Boolean);
    procedure SetShowGeneratedFiles(const Value: Boolean);
  protected
    procedure DoMessage(const Msg: string);
    procedure WriteDtx(ATypeList: TTypeList);
    procedure FillWithHeaders(ATypeList: TTypeList; Optional, NotOptional: TStrings);
    procedure CompareDtxFile(const AFileName: string; DtxHeaders: TStrings; ATypeList: TTypeList);
    procedure SettingsChanged(Sender: TObject; ChangeType: TSettingsChangeType);
    procedure DetermineCheckable(CheckableList, NotInPasDir, NotInRealDtxDir: TStrings);
    procedure GetAllFilesFrom(const ADir, AFilter: string; AFiles: TStrings);
    procedure UpdateFiles;
    procedure FilterFiles(AllList, FilteredList: TStrings);
  public
    constructor Create; virtual;
    destructor Destroy; override;

    procedure GenerateDtxFile(const AFileName: string);
    procedure GenerateDtxFiles;

    procedure CheckDtxFile(const AFileName: string);
    procedure CheckDtxFiles;

    procedure RefreshFiles;

    procedure AddToIgnoreList(const S: string);
    procedure AddToCompletedList(const S: string);

    property SkipList: TStrings read FSkipList write FSkipList;
    property ProcessList: TStrings read FProcessList write FProcessList;
    property MessagesList: TStrings read FMessagesList write FMessagesList;

    property ShowCompletedFiles: Boolean read FShowCompletedFiles write SetShowCompletedFiles;
    property ShowIgnoredFiles: Boolean read FShowIgnoredFiles write SetShowIgnoredFiles;
    property ShowGeneratedFiles: Boolean read FShowGeneratedFiles write SetShowGeneratedFiles;
    property ShowOtherFiles: Boolean read FShowOtherFiles write SetShowOtherFiles;
  end;

implementation

uses
  SysUtils,
  JclFileUtils, JvProgressDialog, JvSearchFiles,
  DelphiParser;

const
  {TDelphiType = (dtClass, dtConst, dtDispInterface, dtFunction, dtFunctionType,
    dtInterface, dtMethodFunc, dtMethodProc, dtProcedure, dtProcedureType,
    dtProperty, dtRecord, dtResourceString, dtSet, dtType, dtVar);}
  {TOutputType = (otClass, otConst, otDispInterface, otFunction, otFunctionType,
    otInterface, otProcedure, otProcedureType, otProperty, otRecord,
    otResourceString, otSet, otType, otVar);}

  CConvert: array[TDelphiType] of TOutputType =
  (otClass, otConst, otType, otFunction, otFunctionType,
    otType, otFunction, otProcedure, otProcedure, otProcedureType,
    otProperty, otRecord, otResourcestring, otSet, otType, otVar);

procedure DiffLists(Source1, Source2, InBoth, NotInSource1, NotInSource2: TStrings);
var
  Index1, Index2: Integer;
  C: Integer;
begin
  {if (Source1 is TStringList) and not (TStringList(Source1).Sorted) then
    raise Exception.Create('Not sorted');
  if (Source2 is TStringList) and not (TStringList(Source2).Sorted) then
    raise Exception.Create('Not sorted');}

  if not Assigned(Source1) or not Assigned(Source2) then
    Exit;

  Index1 := 0;
  Index2 := 0;
  while (Index1 < Source1.Count) and (Index2 < Source2.Count) do
  begin
    C := AnsiCompareText(Source1[Index1], Source2[Index2]);
    if C = 0 then
    begin
      if Assigned(InBoth) then
        InBoth.Add(Source1[Index1]);
      Inc(Index1);
      Inc(Index2);
    end
    else
      if C < 0 then
    begin
      if Assigned(NotInSource2) then
        NotInSource2.Add(Source1[Index1]);
      Inc(Index1)
    end
    else
      if C > 0 then
    begin
      if Assigned(NotInSource1) then
        NotInSource1.Add(Source2[Index2]);
      Inc(Index2);
    end;
  end;

  if Assigned(NotInSource1) then
    while Index2 < Source2.Count do
    begin
      NotInSource1.Add(Source2[Index2]);
      Inc(Index2);
    end;
  if Assigned(NotInSource2) then
    while Index1 < Source1.Count do
    begin
      NotInSource2.Add(Source1[Index1]);
      Inc(Index1);
    end;
end;

procedure ExcludeList(Source, RemoveList: TStrings);
var
  SourceIndex, RemoveIndex: Integer;
  C: Integer;
begin
  {if (Source is TStringList) and not (TStringList(Source).Sorted) then
    raise Exception.Create('Not sorted');
  if (RemoveList is TStringList) and not (TStringList(RemoveList).Sorted) then
    raise Exception.Create('Not sorted');}

  SourceIndex := 0;
  RemoveIndex := 0;
  while (SourceIndex < Source.Count) and (RemoveIndex < RemoveList.Count) do
  begin
    C := AnsiCompareText(Source[SourceIndex], RemoveList[RemoveIndex]);
    if C = 0 then
    begin
      Source.Delete(SourceIndex);
      Inc(RemoveIndex);
    end
    else
      if C < 0 then
      Inc(SourceIndex)
    else
      if C > 0 then
      Inc(RemoveIndex);
  end;
end;

function GetClassInfoStr(AItem: TAbstractItem): string;
begin
  if (AItem.DelphiType = dtClass) and TSettings.Instance.IsRegisteredClass(AItem.SimpleName) then
    Result := Format(CClassInfo, [AItem.SimpleName])
  else
    Result := '';
end;

function GetTitleStr(AItem: TAbstractItem): string;
begin
  if AITem.TitleName > '' then
    Result := Format('<TITLE %s>', [AItem.TitleName])
  else
    Result := '';
end;

function GetSummaryStr(AItem: TAbstractItem): string;
begin
  if (AItem.DelphiType in [dtMethodFunc, dtMethodProc]) and (AItem is TParamClassMethod) and
    (diOverride in TParamClassMethod(AItem).Directives) then

    Result := CSummaryDescriptionOverride
  else
    Result := CSummaryDescription;
end;

function GetDescriptionStr(AItem: TAbstractItem): string;
begin
  Result := CDescriptionDescription + AItem.AddDescriptionString;
end;

function GetCombineStr(AItem: TAbstractItem): string;
begin
  if AITem.CombineString > '' then
    Result := Format('<COMBINE %s>', [AItem.CombineString])
  else
    Result := '';

  (*
  Result := '';
  if AItem.DelphiType <> dtType then
    Exit;

  S := AItem.ValueString;
  if S = '' then
    Exit;

  if StrLIComp(PChar(S), 'set of', 6) = 0 then
  begin
    S := Trim(Copy(S, 8, MaxInt));
    while (Length(S) > 0) and (S[Length(S)] in [' ', ';']) do
      Delete(S, Length(S), 1);
    Result := Format('<COMBINE %s>'#13#10, [S]);
    Exit;
  end;

  if S[1] = '^' then
  begin
    Delete(S, 1, 1);
    S := Trim(S);
    while (Length(S) > 0) and (S[Length(S)] in [' ', ';']) do
      Delete(S, Length(S), 1);
    Result := Format('<COMBINE %s>'#13#10, [S]);
    Exit;
  end;*)
end;

function GetParamStr(AItem: TAbstractItem): string;
begin
  Result := AItem.ParamString;
  if Result > '' then
    Result := CParamDescription + Result;
end;

function GetReturnsStr(AItem: TAbstractItem): string;
begin
  if AItem.DelphiType in [dtFunction, dtProcedure] then
    Result := ''
  else
    Result := CReturnsDescription;
end;

{ TMainCtrl }

procedure TMainCtrl.AddToCompletedList(const S: string);
var
  I: Integer;
begin
  TSettings.Instance.AddToUnitStatus(usCompleted, S);

  if not ShowCompletedFiles then
  begin
    I := SkipList.IndexOf(S);
    if I >= 0 then
      SkipList.Delete(I);
    I := ProcessList.IndexOf(S);
    if I >= 0 then
      ProcessList.Delete(I);
  end;
end;

procedure TMainCtrl.AddToIgnoreList(const S: string);
var
  I: Integer;
begin
  TSettings.Instance.AddToUnitStatus(usIgnored, S);
  if not ShowIgnoredFiles then
  begin
    I := SkipList.IndexOf(S);
    if I >= 0 then
      SkipList.Delete(I);
    I := ProcessList.IndexOf(S);
    if I >= 0 then
      ProcessList.Delete(I);
  end;
end;

constructor TMainCtrl.Create;
begin
  TSettings.Instance.RegisterObserver(Self, SettingsChanged);

  FAllFiles := TStringList.Create;
  with FAllFiles do
  begin
    Sorted := True;
    Duplicates := dupIgnore;
    CaseSensitive := False;
  end;

  FAllFilteredFiles := TStringList.Create;
  with FAllFilteredFiles do
  begin
    Sorted := True;
    Duplicates := dupIgnore;
    CaseSensitive := False;
  end;

  FShowGeneratedFiles := True;
  FShowOtherFiles := False;
  FShowIgnoredFiles := False;
  FShowCompletedFiles := False;
end;

destructor TMainCtrl.Destroy;
begin
  TSettings.Instance.UnRegisterObserver(Self);
  FAllFilteredFiles.Free;
  FAllFiles.Free;
  inherited;
end;

procedure TMainCtrl.DoMessage(const Msg: string);
begin
  if Assigned(MessagesList) then
    MessagesList.Add(Msg);
end;

procedure TMainCtrl.FilterFiles(AllList, FilteredList: TStrings);
var
  I: Integer;
  LIsCompletedUnit: Boolean;
  LIsIgnoredUnit: Boolean;
  LIsGeneratedUnit: Boolean;
  LDoAdd: Boolean;
begin
  AllList.AddStrings(FilteredList);

  FilteredList.BeginUpdate;
  try
    FilteredList.Clear;
    for I := 0 to AllList.Count - 1 do
      with TSettings.Instance do
      begin
        LIsCompletedUnit := False;
        LIsIgnoredUnit := False;
        LIsGeneratedUnit := False;

        if ShowCompletedFiles or ShowOtherFiles then
          LIsCompletedUnit := IsUnitFrom(usCompleted, AllList[I]);
        LDoAdd := ShowCompletedFiles and LIsCompletedUnit;
        if not LDoAdd then
        begin
          if ShowIgnoredFiles or ShowOtherFiles then
            LIsIgnoredUnit := IsUnitFrom(usIgnored, AllList[I]);
          LDoAdd := ShowIgnoredFiles and LIsIgnoredUnit;
          if not LDoAdd then
          begin
            if ShowGeneratedFiles or ShowOtherFiles then
              LIsGeneratedUnit := IsUnitFrom(usGenerated, AllList[I]);
            LDoAdd := (ShowGeneratedFiles and LIsGeneratedUnit) or
              (ShowOtherFiles and not LIsCompletedUnit and not LIsIgnoredUnit and not LIsGeneratedUnit);
          end;
        end;
        if LDoAdd then
          FilteredList.Add(AllList[I])
      end;
  finally
    FilteredList.EndUpdate;
  end;
end;

procedure TMainCtrl.GenerateDtxFiles;
var
  I: Integer;
  Dir: string;
  ProgressDlg: TJvProgressDialog;
begin
  if not Assigned(ProcessList) then
    Exit;
  Dir := IncludeTrailingPathDelimiter(TSettings.Instance.PasDir);
  FParsedOK := 0;
  FParsedError := 0;

  ProgressDlg := TJvProgressDialog.Create(nil);
  try
    ProgressDlg.Min := 0;
    ProgressDlg.Max := ProcessList.Count;
    ProgressDlg.Caption := 'Progress';
    ProgressDlg.Show;

    for I := 0 to ProcessList.Count - 1 do
    begin
      ProgressDlg.Text := ProcessList[I];
      ProgressDlg.Position := I;
      GenerateDtxFile(Dir + ProcessList[I]);
    end;

    DoMessage(Format('Errors %d OK %d Total %d',
      [FParsedError, FParsedOK, FParsedError + FParsedOK]));
  finally
    ProgressDlg.Hide;
    ProgressDlg.Free;
  end;
end;

procedure TMainCtrl.GenerateDtxFile(const AFileName: string);
var
  Parser: TDelphiParser;
begin
  Parser := TDelphiParser.Create;
  try
    Parser.AcceptCompilerDirectives := TSettings.Instance.AcceptCompilerDirectives;
    if Parser.Execute(ChangeFileExt(AFileName, '.pas')) then
    begin
      Inc(FParsedOK);
      WriteDtx(Parser.TypeList);
    end
    else
    begin
      Inc(FParsedError);
      DoMessage(Format('[Error] %s - %s', [AFileName, Parser.ErrorMsg]));
    end;
  finally
    Parser.Free;
  end;
end;

procedure TMainCtrl.RefreshFiles;
begin
  GetAllFilesFrom(TSettings.Instance.PasDir, '*.pas', FAllFiles);
  UpdateFiles;
end;

{procedure TMainCtrl.RemoveIgnoredFiles;
var
  I: Integer;
begin
  if Assigned(FProcessList) then
    with FProcessList do
    begin
      BeginUpdate;
      try
        for I := Count - 1 downto 0 do
          if (FIgnoreFiles and TSettings.Instance.IsIgnoredUnit(Strings[I])) or
            (FIgnoreCompletedFiles and TSettings.Instance.IsCompletedUnit(Strings[I])) then
            Delete(I);
      finally
        EndUpdate;
      end;
    end;

  if Assigned(FSkipList) then
    with FSkipList do
    begin
      BeginUpdate;
      try
        for I := Count - 1 downto 0 do
          if (FIgnoreFiles and TSettings.Instance.IsIgnoredUnit(Strings[I])) or
            (FIgnoreCompletedFiles and TSettings.Instance.IsCompletedUnit(Strings[I])) then
            Delete(I);
      finally
        EndUpdate;
      end;
    end;
end;}

{procedure TMainCtrl.SetIgnoreCompletedFiles(const Value: Boolean);
begin
  if Value = FIgnoreCompletedFiles then
    Exit;

  FIgnoreCompletedFiles := Value;
  if FIgnoreCompletedFiles then
    RemoveIgnoredFiles
  else
    UpdateSourceFiles;
end;}

{procedure TMainCtrl.SetIgnoreFiles(const Value: Boolean);
begin
  if Value = FIgnoreFiles then
    Exit;

  FIgnoreFiles := Value;
  if FIgnoreFiles then
    RemoveIgnoredFiles
  else
    UpdateSourceFiles;
end;}

procedure TMainCtrl.SetShowCompletedFiles(const Value: Boolean);
begin
  if FShowCompletedFiles <> Value then
  begin
    FShowCompletedFiles := Value;
    UpdateFiles;
  end;
end;

procedure TMainCtrl.SetShowGeneratedFiles(const Value: Boolean);
begin
  if FShowGeneratedFiles <> Value then
  begin
    FShowGeneratedFiles := Value;
    UpdateFiles;
  end;
end;

procedure TMainCtrl.SetShowIgnoredFiles(const Value: Boolean);
begin
  if FShowIgnoredFiles <> Value then
  begin
    FShowIgnoredFiles := Value;
    UpdateFiles;
  end;
end;

procedure TMainCtrl.SetShowOtherFiles(const Value: Boolean);
begin
  if FShowOtherFiles <> Value then
  begin
    FShowOtherFiles := Value;
    UpdateFiles;
  end;
end;

procedure TMainCtrl.SettingsChanged(Sender: TObject;
  ChangeType: TSettingsChangeType);
begin
  case ChangeType of
    ctPasDirectory: RefreshFiles;
    ctGeneratedDtxDirectory: ;
    ctRealDtxDirectory: ;
  end;
end;

procedure TMainCtrl.WriteDtx(ATypeList: TTypeList);
var
  FileName: string;
  FileStream: TFileStream;

  function GetOutputStr(const OutputType: TOutputType; const AName: string): string;
  var
    Index: Integer;
  begin
    with TSettings.Instance do
    begin
      Index := OutputTypeDesc[OutputType].IndexOf(UpperCase(AName));
      if Index < 0 then
        Result := OutputTypeDefaults[OutputType]
      else
        Result := OutputTypeStrings[OutputType][Index];
    end;
  end;

  procedure WriteClassHeader(ATypeItem: TAbstractItem);
  var
    S: string;
  begin
    //S := TSettings.Instance.OutputTypeDefaults[otClassHeader];
    S := GetOutputStr(otClassHeader, ATypeItem.SimpleName);
    S := StringReplace(S, '%author', ATypeList.Author, [rfReplaceAll,
      rfIgnoreCase]);
    S := StringReplace(S, '%simplename', ATypeItem.SimpleName, [rfReplaceAll,
      rfIgnoreCase]);
    S := StringReplace(S, '%referencename', ATypeItem.ReferenceName, [rfReplaceAll, rfIgnoreCase]);
    S := StringReplace(S, '%sortname', ATypeItem.SortName, [rfReplaceAll, rfIgnoreCase]);
    S := StringReplace(S, '%titlename', ATypeItem.TitleName, [rfReplaceAll, rfIgnoreCase]);
    S := StringReplace(S, '%title', GetTitleStr(ATypeItem), [rfReplaceAll, rfIgnoreCase]);
    S := StringReplace(S, '%param', ATypeItem.ParamString, [rfReplaceAll,
      rfIgnoreCase]);
    S := StringReplace(S, '%items', ATypeItem.ItemsString, [rfReplaceAll,
      rfIgnoreCase]);
    S := StringReplace(S, '%nicename',
      TSettings.Instance.NiceName[ATypeItem.ClassString], [rfReplaceAll,
      rfIgnoreCase]);
    FileStream.Write(PChar(S)^, Length(S));
  end;

  procedure WriteHeader;
  var
    S: string;
    UnitName: string;
  begin
    UnitName := ChangeFileExt(ExtractFileName(FileName), '');
    S := TSettings.Instance.OutputTypeDefaults[otHeader];
    S := StringReplace(S, '%author', ATypeList.Author, [rfReplaceAll,
      rfIgnoreCase]);
    S := StringReplace(S, '%unitname', UnitName, [rfReplaceAll, rfIgnoreCase]);
    FileStream.Write(PChar(S)^, Length(S));
  end;

  procedure WriteType(ATypeItem: TAbstractItem);
  var
    S: string;
  begin
    { Inherited properties [property X;] niet toevoegen }
    if (ATypeItem is TMethodProp) and (TMethodProp(ATypeItem).InheritedProp) then
      Exit;

    { Create, Destroy ook niet }
    if SameText(ATypeItem.SimpleName, 'create') or SameText(ATypeItem.SimpleName, 'destroy') then
      Exit;

    if not TSettings.Instance.OutputTypeEnabled[CConvert[ATypeItem.DelphiType]] then
      Exit;
    //S := TSettings.Instance.OutputTypeDefaults[CConvert[ATypeItem.DelphiType]];

    S := GetOutputStr(CConvert[ATypeItem.DelphiType], ATypeItem.SimpleName);

    S := StringReplace(S, '%author', ATypeList.Author, [rfReplaceAll, rfIgnoreCase]);
    S := StringReplace(S, '%name', ATypeItem.SimpleName, [rfReplaceAll, rfIgnoreCase]);
    S := StringReplace(S, '%classinfo', GetClassInfoStr(ATypeItem), [rfReplaceAll, rfIgnoreCase]);
    S := StringReplace(S, '%titlename', ATypeItem.TitleName, [rfReplaceAll, rfIgnoreCase]);
    S := StringReplace(S, '%title', GetTitleStr(ATypeItem), [rfReplaceAll, rfIgnoreCase]);
    S := StringReplace(S, '%referencename', ATypeItem.ReferenceName, [rfReplaceAll, rfIgnoreCase]);
    S := StringReplace(S, '%sortname', ATypeItem.SortName, [rfReplaceAll, rfIgnoreCase]);
    S := StringReplace(S, '%param', GetParamStr(ATypeItem), [rfReplaceAll, rfIgnoreCase]);
    S := StringReplace(S, '%items', ATypeItem.ItemsString, [rfReplaceAll, rfIgnoreCase]);
    S := StringReplace(S, '%class', ATypeItem.ClassString, [rfReplaceAll, rfIgnoreCase]);
    S := StringReplace(S, '%nicename', TSettings.Instance.NiceName[ATypeItem.ClassString], [rfReplaceAll,
      rfIgnoreCase]);
    if not ATypeItem.CanCombine then
    begin
      S := StringReplace(S, '%summary', GetSummaryStr(ATypeItem), [rfReplaceAll, rfIgnoreCase]);
      S := StringReplace(S, '%description', GetDescriptionStr(ATypeItem), [rfReplaceAll, rfIgnoreCase]);
      S := StringReplace(S, '%seealso', CSeeAlsoDescription, [rfReplaceAll, rfIgnoreCase]);
      S := StringReplace(S, '%returns', GetReturnsStr(ATypeItem), [rfReplaceAll, rfIgnoreCase]);
      S := StringReplace(S, '%combine', '', [rfReplaceAll, rfIgnoreCase]);
      S := StringReplace(S, '%refvalue', CValueReference, [rfReplaceAll, rfIgnoreCase]);
      S := StringReplace(S, '%value', ATypeItem.ValueString, [rfReplaceAll, rfIgnoreCase]);
    end
    else
    begin
      S := StringReplace(S, '%summary', '', [rfReplaceAll, rfIgnoreCase]);
      S := StringReplace(S, '%description', '', [rfReplaceAll, rfIgnoreCase]);
      S := StringReplace(S, '%seealso', '', [rfReplaceAll, rfIgnoreCase]);
      S := StringReplace(S, '%returns', '', [rfReplaceAll, rfIgnoreCase]);
      S := StringReplace(S, '%combine', GetCombineStr(ATypeItem), [rfReplaceAll, rfIgnoreCase]);
      S := StringReplace(S, '%refvalue', '', [rfReplaceAll, rfIgnoreCase]);
      S := StringReplace(S, '%value', '', [rfReplaceAll, rfIgnoreCase]);
    end;
    S := Trim(S) + #13#10#13#10;
    S := Trim(StringReplace(S, #13#10#13#10, #13#10, [rfReplaceAll]));
    S := Trim(StringReplace(S, #13#10#13#10, #13#10, [rfReplaceAll]));
    S := S + #13#10;

    FileStream.Write(PChar(S)^, Length(S));
  end;

var
  I: Integer;
begin
  FileName := IncludeTrailingPathDelimiter(TSettings.Instance.GeneratedDtxDir) +
    ChangeFileExt(ExtractFileName(ATypeList.FileName), '.dtx');
  if FileExists(FileName) and not TSettings.Instance.OverwriteExisting then
    Exit;

  FileStream := TFileStream.Create(FileName, fmCreate);
  try
    { Eerst de classheaders }
    if TSettings.Instance.OutputTypeEnabled[otClassHeader] then
      for I := 0 to ATypeList.Count - 1 do
        if ATypeList[I] is TClassItem then
          WriteClassHeader(ATypeList[I]);

    { Dan de header }
    if TSettings.Instance.OutputTypeEnabled[otHeader] then
      WriteHeader;

    { Dan de rest }
    for I := 0 to ATypeList.Count - 1 do
      WriteType(ATypeList[I]);
  finally
    FileStream.Free;
  end;
end;

procedure TMainCtrl.CheckDtxFile(const AFileName: string);
var
  DelphiParser: TDelphiParser;
  DtxParser: TCompareParser;
begin
  DelphiParser := TDelphiParser.Create;
  DtxParser := TCompareParser.Create;
  try
    DelphiParser.AcceptCompilerDirectives := TSettings.Instance.AcceptCompilerDirectives;
    DelphiParser.AcceptVisibilities := [inProtected, inPublic, inPublished];

    if not DelphiParser.Execute(IncludeTrailingPathDelimiter(TSettings.Instance.PasDir) +
      ChangeFileExt(AFileName, '.pas')) then
    begin
      Inc(FParsedError);
      DoMessage(Format('[Error] %s - %s', [AFileName, DelphiParser.ErrorMsg]));
      Exit;
    end;

    if not DtxParser.Execute(IncludeTrailingPathDelimiter(TSettings.Instance.RealDtxDir) +
      ChangeFileExt(AFileName, '.dtx')) then
    begin
      Inc(FParsedError);
      DoMessage(Format('[Error] %s - %s', [AFileName, '..']));
      Exit;
    end;

    CompareDtxFile(AFileName, DtxParser.List, DelphiParser.TypeList);

    Inc(FParsedOK);
    //WriteDtx(Parser.TypeList);
  finally
    DtxParser.Free;
    DelphiParser.Free;
  end;
end;

procedure TMainCtrl.CheckDtxFiles;
var
  I: Integer;
  ProgressDlg: TJvProgressDialog;

  NotInPasDir: TStringList;
  NotInRealDtxDir: TStringList;
  CheckableList: TStringList;
begin
  if not Assigned(ProcessList) then
    Exit;

  NotInPasDir := TStringList.Create;
  NotInRealDtxDir := TStringList.Create;
  CheckableList := TStringList.Create;
  try
    CheckableList.Sorted := True;
    NotInPasDir.Sorted := True;
    NotInRealDtxDir.Sorted := True;

    DetermineCheckable(CheckableList, NotInPasDir, NotInRealDtxDir);

    if NotInPasDir.Count > 0 then
    begin
      DoMessage('Not found in *.pas directory');
      for I := 0 to NotInPasDir.Count - 1 do
        DoMessage(NotInPasDir[I]);
      DoMessage('--');
    end;
    if NotInRealDtxDir.Count > 0 then
    begin
      DoMessage('Not found in *.dtx directory');
      for I := 0 to NotInRealDtxDir.Count - 1 do
        DoMessage(NotInRealDtxDir[I]);
      DoMessage('--');
    end;
    if CheckableList.Count = 0 then
    begin
      DoMessage('Nothing to do');
      DoMessage('--');
      Exit;
    end;

    FParsedOK := 0;
    FParsedError := 0;
    ProgressDlg := TJvProgressDialog.Create(nil);
    try
      ProgressDlg.Min := 0;
      ProgressDlg.Max := CheckableList.Count;
      ProgressDlg.Caption := 'Progress';
      ProgressDlg.Show;

      for I := 0 to CheckableList.Count - 1 do
      begin
        ProgressDlg.Text := CheckableList[I];
        ProgressDlg.Position := I;
        CheckDtxFile(CheckableList[I]);
      end;
      DoMessage('Done');
      DoMessage('--');
      DoMessage(Format('Errors %d OK %d Total %d',
        [FParsedError, FParsedOK, FParsedError + FParsedOK]));
    finally
      ProgressDlg.Hide;
      ProgressDlg.Free;
    end;
  finally
    NotInPasDir.Free;
    NotInRealDtxDir.Free;
    CheckableList.Free;
  end;
end;

procedure TMainCtrl.DetermineCheckable(CheckableList, NotInPasDir,
  NotInRealDtxDir: TStrings);
var
  AllFilesInPasDir: TStringList;
  AllFilesInRealDtxDir: TStringList;
  AllFiles: TStringList;
begin
  AllFilesInPasDir := TStringList.Create;
  AllFilesInRealDtxDir := TStringList.Create;
  AllFiles := TStringList.Create;
  try
    AllFilesInPasDir.Sorted := True;
    AllFilesInRealDtxDir.Sorted := True;
    AllFiles.Sorted := True;

    GetAllFilesFrom(TSettings.Instance.PasDir, '*.pas', AllFilesInPasDir);
    GetAllFilesFrom(TSettings.Instance.RealDtxDir, '*.dtx', AllFilesInRealDtxDir);

    DiffLists(ProcessList, AllFilesInPasDir, CheckableList, nil, NotInPasDir);
    DiffLists(ProcessList, AllFilesInRealDtxDir, CheckableList, nil, NotInRealDtxDir);
    ExcludeList(CheckableList, NotInPasDir);
    ExcludeList(CheckableList, NotInRealDtxDir);
  finally
    AllFiles.Free;
    AllFilesInPasDir.Free;
    AllFilesInRealDtxDir.Free;
  end;
end;

procedure TMainCtrl.GetAllFilesFrom(const ADir, AFilter: string;
  AFiles: TStrings);
var
  I: Integer;
begin
  AFiles.BeginUpdate;
  try
    AFiles.Clear;

    with TJvSearchFiles.Create(nil) do
    try
      DirOption := doExcludeSubDirs;
      RootDirectory := ADir;
      Options := [soSearchFiles, soSorted, soStripDirs];
      ErrorResponse := erRaise;
      DirParams.SearchTypes := [];
      FileParams.SearchTypes := [stFileMask];
      FileParams.FileMask := AFilter;

      Search;

      for I := 0 to Files.Count - 1 do
        AFiles.Add(ChangeFileExt(Files[I], ''));
    finally
      Free;
    end;
  finally
    AFiles.EndUpdate;
  end;
end;

procedure TMainCtrl.CompareDtxFile(const AFileName: string; DtxHeaders: TStrings;
  ATypeList: TTypeList);
var
  I: Integer;
  Optional: TStringList;
  NotOptional: TStringList;
  NotInDtx, NotInPas: TStringList;
begin
  Optional := TStringList.Create;
  NotOptional := TStringList.Create;
  NotInDtx := TStringList.Create;
  NotInPas := TStringList.Create;
  try
    Optional.Sorted := True;
    NotOptional.Sorted := True;
    NotInDtx.Sorted := True;
    NotInPas.Sorted := True;

    FillWithHeaders(ATypeList, Optional, NotOptional);
    NotOptional.Add('@@' + ChangeFileExt(AFileName, '.pas'));
    NotOptional.SaveToFile('C:\Temp\NotOptional.txt');
    DtxHeaders.SaveToFile('C:\Temp\DtxHeaders.txt');

    DiffLists(DtxHeaders, NotOptional, nil, NotInDtx, NotInPas);
    ExcludeList(NotInPas, Optional);
    ExcludeList(NotInDtx, Optional);

    if (NotInDtx.Count = 0) and (NotInPas.Count = 0) then
    begin
      DoMessage(Format('------------Comparing %s .... Ok', [AFileName]));
      Exit;
    end;

    DoMessage(Format('------------Comparing %s .... Differs', [AFileName]));
    if NotInDtx.Count > 0 then
    begin
      DoMessage('Not in dtx file');
      for I := 0 to NotInDtx.Count - 1 do
        DoMessage(NotInDtx[I]);
    end;
    if NotInPas.Count > 0 then
    begin
      DoMessage('Not in pas file');
      for I := 0 to NotInPas.Count - 1 do
        DoMessage(NotInPas[I]);
    end;
  finally
    Optional.Free;
    NotOptional.Free;
    NotInDtx.Free;
    NotInPas.Free;
  end;
end;

procedure TMainCtrl.FillWithHeaders(ATypeList: TTypeList; Optional,
  NotOptional: TStrings);
var
  I: Integer;
  ATypeItem: TAbstractItem;
  S: string;
  IsOptional: Boolean;
begin
  for I := 0 to ATypeList.Count - 1 do
  begin
    ATypeItem := ATypeList[I];

    S := '@@' + ATypeItem.ReferenceName;

    if TSettings.Instance.OutputTypeEnabled[CConvert[ATypeItem.DelphiType]] then
    begin
      IsOptional :=
        { private,protected members are optional }
      ((ATypeItem is TClassMethod) and (TClassMethod(ATypeItem).Position in [inPrivate, inProtected]))

      or

      { overridden methods are optional }
      ((ATypeItem is TParamClassMethod) and (diOverride in TParamClassMethod(ATypeItem).Directives))

      or

      { inherited properties are optional }
      ((ATypeItem is TMethodProp) and (TMethodProp(ATypeItem).InheritedProp))

      or

      { create, destroy are optional}
      ((ATypeItem is TParamClassMethod) and
        (SameText(ATypeItem.SimpleName, 'create') or SameText(ATypeItem.SimpleName, 'destroy')));

      if IsOptional then
        Optional.Add(S)
      else
        NotOptional.Add(S);

      if ATypeItem is TListItem then
        TListItem(ATypeItem).AddToList(NotOptional);
    end;
  end;
end;

procedure TMainCtrl.UpdateFiles;
var
  NewSkipList: TStringList;
begin
  NewSkipList := TStringList.Create;
  try
    NewSkipList.Sorted := True;

    SkipList.BeginUpdate;
    ProcessList.BeginUpdate;
    try
      FilterFiles(FAllFiles, FAllFilteredFiles);
      DiffLists(FAllFilteredFiles, SkipList, NewSkipList, nil, nil);

      ProcessList.Assign(FAllFilteredFiles);
      ExcludeList(ProcessList, NewSkipList);
      SkipList.Assign(NewSkipList);
    finally
      ProcessList.EndUpdate;
      SkipList.EndUpdate;
    end;
  finally
    NewSkipList.Free;
  end;
end;

end.

