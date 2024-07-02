program cloudflaredns;

{$mode objfpc}{$H+}
{$warn 6058 off}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes,
  SysUtils,
  CustApp,
  jsonparser,
  fpjson,
  IdGlobal,
  IdSSLOpenSSL,
  IdHTTP,
  fgl;

const
  _JSONFile      = 'config.json';
  _GetPubIPURL   = 'https://domains.google.com/checkip';
  _TempPubIPFile = 'ip.txt';
  //_AppURL        = 'https://github.com/D3lphi3r/cloudflare-dns';
  _LogFileName   = 'logs.txt';
  _APIBase       = 'https://api.cloudflare.com/client/v4/zones/%s/dns_records/%s';
  _ParamSkip     = 'skip';
  _ParamLog      = 'log';
  _ParamHelp     = 'help';
  _ParamSilent   = 'Silent';
  _ParamGetIDs   = 'ids';
  //_Version       = '1.0';

type
  PHostInfo = ^THostInfo;
  THostInfo = record
    Host    : string;
    ID      : string;
    Proxied : Boolean;
  end;

  THostInfoList = specialize TFPGList<PHostInfo>;

type

  { TCloudflareDNS }

  TCloudflareDNS = class(TCustomApplication)
  private
    FPubIP          : string;
    IdHTTP          : TIdHTTP;
    FLogs           : TStringList;
    FZoneID         : string;
    FToken          : string;
    FHostInfoList   : THostInfoList;
    FLogFile        : Boolean;
    FLogConsole     : Boolean;
    FSkipPupIPCheck : Boolean;
    FPrintRecordIDs : Boolean;
    IdSSL           : TIdSSLIOHandlerSocketOpenSSL;
    function GetPublicIP(): string;
    procedure LogMessage(const AMessage: string);
    procedure GetRecordIDs();
    function UpdateDNSRecord(const AID, AHost: string; AProxied : Boolean): Boolean;
  protected
    procedure DoRun; override;
  public
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
    procedure WriteHelp; virtual;
  end;

function _StringToFile(const AString, AFileName: string; AEncoding: TEncoding = nil): Boolean;
var
{$IFDEF FPC}
  Stream : TStringStream;
{$ELSE}
  Stream : TStreamWriter;
{$ENDIF}
begin
  Result := False;
  if not DirectoryExists(ExtractFilePath(AFileName)) then
    ForceDirectories(ExtractFilePath(AFileName));
  if not DirectoryExists(ExtractFilePath(AFileName)) then Exit;
  if AEncoding <> nil then begin
    {$IFDEF FPC}
    Stream := TStringStream.Create( AString, AEncoding)
    {$ELSE}
    Stream := TStreamWriter.Create(AFileName, False, AEncoding)
    {$ENDIF}
  end
  else begin
    {$IFDEF FPC}
    Stream := TStringStream.Create( AString, TEncoding.ASCII);
    {$ELSE}
    Stream := TStreamWriter.Create(AFileName, False, TEncoding.ASCII);
    {$ENDIF}

  end;
  try
    {$IFDEF FPC}
    Stream.SaveToFile(AFileName);
    {$ELSE}
    Stream.Write(AString);
    {$ENDIF}
    Result := True;
  except
     On E: Exception Do begin
     Raise Exception.Create(E.Message);
     end;
  end;
    if Stream <> nil then Stream.Free;
end;

function _FileToString(const AFileName: string; AEncoding: TEncoding = nil): string;
var
  Strings : TStringList;
begin
  Result := '';
  if not FileExists(AFileName) then Exit;
  Strings := TStringList.Create;
  try
    if AEncoding = nil then
      AEncoding := TEncoding.ASCII;
    Strings.LoadFromFile(AFileName, AEncoding);
    Result := Strings.Text;
  finally
     Strings.Free;
  end;
end;

{ TCloudflareDNS }

function TCloudflareDNS.GetPublicIP(): string;
begin
  Result := '';
  try
   Result := IdHTTP.Get(_GetPubIPURL);
  except
    On E: Exception Do begin
      LogMessage('Cant get the public IP :' + E.Message);
    end;
  end;
end;

procedure TCloudflareDNS.LogMessage(const AMessage: string);
var
  S : string;
begin
  S := AMessage;
  if FLogConsole then
    WriteLn(S);
  FLogs.Add(DateTimeToStr(Now) + #9 + S);
end;

procedure TCloudflareDNS.GetRecordIDs();
var
  jData : TJSONData;
  S     : string;
begin
  try
   S := IdHTTP.Get('https://api.cloudflare.com/client/v4/zones/'+FZoneID+'/dns_records');
   try
     jData := GetJSON(S);
     LogMessage(jData.FormatJSON);
   except
     On E: Exception Do begin
       LogMessage('JSON parsing error :' + E.Message);
     end;
   end;
  except
    On E: Exception Do begin
      LogMessage('Cant get the public IP :' + E.Message);
    end;
  end;
end;

function TCloudflareDNS.UpdateDNSRecord(const AID, AHost: string; AProxied : Boolean): Boolean;
var
  HTTPParam : TMemoryStream;
  S : string;
begin
  Result := False;
  S := '{' + EOL  +
      '"content": "'+ FPubIP +'",' + EOL +
      '"name": "'+ AHost +'",' + EOL +
      '"proxied": '+BoolToStr(AProxied, 'true', 'false')+',' + EOL +
      '"type": "A",' + EOL +
      '"comment": "'+ '' +'",' + EOL +
      '"id": "'+ AID +'",' + EOL +
      '"ttl": 1,' + EOL +
      '"zone_id": "'+ FZoneID +'"' + EOL +
      '}';
  HTTPParam := TMemoryStream.Create;
  try
    WriteStringToStream(HTTPParam, S);
    HTTPParam.Position := 0;
    try
      IdHTTP.Patch(Format(_APIBase, [FZoneID, AID]), HTTPParam);
      Result := True;
    except
      On E: Exception Do begin
        LogMessage('Cant get the public IP :' + E.Message);
      end;
    end;
  finally
    HTTPParam.Free;
  end;

end;

procedure TCloudflareDNS.DoRun;
var
  ErrorMsg : String;
  lPupIP   : string;
  I, J, K  : Integer;
  lJItem   : TJSONData;
  ljData   : TJSONData;
  ljObj    : TJSONData;
  ljHost   : TJSONData;
  lID      : string;
  lHost    : string;
  lProxied : Boolean;
  lObjName : String;
  HostInfo : PHostInfo;
begin
  // quick check parameters
  ErrorMsg:=CheckOptions(_ParamHelp[1]+_ParamSkip[1]+_ParamLog[1]+_ParamSilent[1]+_ParamGetIDs[1]
  , _ParamHelp+#32+_ParamSkip+#32+_ParamLog+#32+_ParamSilent+#32+_ParamGetIDs);
  if ErrorMsg<>'' then begin
    ShowException(Exception.Create(ErrorMsg));
    Terminate;
    Exit;
  end;

  // parse parameters
  if HasOption(_ParamHelp[1], _ParamHelp) then begin
    WriteHelp;
    Terminate;
    Exit;
  end;

  // Enable public IP checking since last run if paramter passwd to the command line.
  FSkipPupIPCheck := HasOption(_ParamSkip[1], _ParamSkip);

  // Enable / disable loffing to file.
  FLogFile := HasOption(_ParamLog[1], _ParamLog);

  // Disable console output.
  FLogConsole := NOT HasOption(_ParamSilent[1], _ParamSilent);

  FPrintRecordIDs := HasOption(_ParamGetIDs[1], _ParamGetIDs);


  // Parse the JSON data
  LogMessage('Parsing JSON.');

  LjData := GetJSON(_FileToString(ExtractFilePath(ParamStr(0) ) + _JSONFile));
  try
    for i := 0 to LjData.Count - 1 do
    begin
      LjItem := LjData.Items[i];
      lObjName := TJSONObject(LjData).Names[i];
      if SameText(lObjName, 'zone_id') then
      begin
         FZoneID := LjItem.Value;
         Continue;
      end;
      if SameText(lObjName, 'token') then
      begin
         FToken := LjItem.Value;
         Continue;
      end;
      if SameText(lObjName, 'records') then
      begin
         for j := 0 to LjItem.Count - 1 do
         begin
           LjObj := LjItem.Items[J];
           for K := 0 to LjObj.Count - 1 do
           begin
             LjHost := LjObj.Items[K];
             if SameText(TJSONObject(LjObj).Names[K], 'id') then
             begin
               LID := LjHost.Value;
             end;
             if SameText(TJSONObject(LjObj).Names[K], 'host') then
             begin
               LHost := LjHost.Value;
             end;
             if SameText(TJSONObject(LjObj).Names[K], 'proxied') then
             begin
               LProxied := LjHost.Value;
             end;
           end;

           if ( (Length(LID) > 0) and (Length(LHost) > 0) ) then
           begin
             New(HostInfo);
             HostInfo^.Host    := LHost;
             HostInfo^.ID      := LID;
             HostInfo^.Proxied := LProxied;
             FHostInfoList.Add(HostInfo);
           end;
         end;
         Continue;
      end;
    end;
    LjData.Free;
  except
    On E: Exception Do begin
      LogMessage('Cant parse the JSON data:' + E.Message );
    end;
  end;

  if Length(FToken) > 0 then
  begin
    IdHTTP.Request.CustomHeaders.AddValue('Authorization', 'Bearer ' + FToken);
  end
  else
  begin
    LogMessage('Token parsing error.');
    Terminate;
    Exit;
  end;

  if Length(FZoneID) = 0 then
  begin
    LogMessage('zone-id parsing error.');
    Terminate;
    Exit;
  end;

  if FPrintRecordIDs then
  begin
    GetRecordIDs();
    Terminate;
    Exit;
  end;

  if FHostInfoList.Count <= 1 then
    LogMessage('JSON have been parsed with ' + FHostInfoList.Count.ToString + ' DNS records.')
  else
    LogMessage('JSON have been parsed with ' + FHostInfoList.Count.ToString + ' DNS records.');



  LPupIP := _FileToString(ExtractFilePath(ParamStr(0)) + _TempPubIPFile, TEncoding.UTF8).Trim();
  //FPubIP := LPupIP;
  //Reading the public IP.
  LogMessage('Getting the public IP.');
  FPubIP := GetPublicIP();
  if Length(FPubIP) = 0 then
  begin
    LogMessage('Unable to get public IP.');
     Terminate;
     Exit;
  end;
  if ( SameText(LPupIP, FPubIP) and (NOT FSkipPupIPCheck) ) then
  begin
    LogMessage('Public IP address not changed since last run....exiting.');
    Terminate;
    Exit;
  end;
  LogMessage('Public IP obtained:' + FPubIP);


  if FHostInfoList.Count > 0 then
  begin
    LogMessage('Updating DNS records.');
    //IdHTTP.Request.CustomHeaders.AddValue('Content-Type', 'application/json');
    for I := 0 to FHostInfoList.Count-1 do
    begin
      if UpdateDNSRecord(FHostInfoList[I]^.ID, FHostInfoList[I]^.Host, FHostInfoList[I]^.Proxied)
      then
        WriteLn(FHostInfoList[I]^.Host, ' updated.')
      else
        WriteLn(FHostInfoList[I]^.Host, ' error please refer to log file.');
    end;
  end;

  _StringToFile(FPubIP, ExtractFilePath(ParamStr(0) ) + _TempPubIPFile, TEncoding.UTF8);

  Terminate;
end;

constructor TCloudflareDNS.Create(TheOwner: TComponent);
begin
  inherited Create(TheOwner);
  StopOnException:=True;
  IdHTTP           := TIdHTTP.Create(Self);
  IdSSL            := TIdSSLIOHandlerSocketOpenSSL.Create(IdHTTP);
  IdHTTP.IOHandler := IdSSL;
  FLogFile         := False;
  FLogConsole      := True;
  FPubIP           := '';
  FLogs            := TStringList.Create;
  FHostInfoList    := THostInfoList.Create;
  IdSSL.SSLOptions.SSLVersions := [sslvTLSv1, sslvTLSv1_1, sslvTLSv1_2];
  IdHTTP.Request.UserAgent     := 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/59.0.3071.104 Safari/537.36';
  IdHTTP.Request.ContentType   := 'application/json';
end;

destructor TCloudflareDNS.Destroy;
var
  I : Integer;
begin
  IdHTTP.Free;
  if FLogFile then
     FLogs.SaveToFile(ExtractFilePath(ParamStr(0) ) + _LogFileName);
  FLogs.Free;
  For i := 0 to FHostInfoList.Count-1 do
  begin
    Dispose(FHostInfoList[I]);
  end;
  FHostInfoList.Free;
  inherited Destroy;
end;

procedure TCloudflareDNS.WriteHelp;
begin
  { add your help code here }
  Writeln('Usage: ', ExeName, ' -h');
end;

var
  Application: TCloudflareDNS;
begin
  Application:=TCloudflareDNS.Create(nil);
  Application.Title:=' Cloudflare DNS';
  Application.Run;
  Application.Free;
end.

