; Warique-Setup.exe: asistente de instalacion y actualizacion para la PC del local.
; Lo compila build-release.ps1 -WithInstaller (Inno Setup 6):
;   ISCC.exe /DAppVersion=0.3.0 /DPackageDir=<release\warique-0.3.0> warique.iss
; Extrae el paquete en C:\ProgramData\WariqueInstalador y ejecuta scripts\setup-run.ps1, que usa los
; mismos install.ps1 / update.ps1 verificados en el CI. Si C:\Warique ya existe, actualiza.
; Instalacion desatendida (CI): /VERYSILENT /SUPPRESSMSGBOXES /GDRIVE=1 [/MYSQLSERVICE=MySQL84], con las claves en las
; variables de entorno WARIQUE_MYSQL_ADMIN_PASSWORD, OWNER_USERNAME, OWNER_FULL_NAME, OWNER_PASSWORD.

#ifndef AppVersion
  #error Falta /DAppVersion
#endif
#ifndef PackageDir
  #error Falta /DPackageDir
#endif

[Setup]
AppId={{8F3C2B1E-5A4D-4E7B-9C61-2D7A0F4B9E31}
AppName=Warique
AppVersion={#AppVersion}
AppVerName=Warique {#AppVersion}
AppPublisher=Warique
DefaultDirName={commonappdata}\WariqueInstalador
DisableDirPage=yes
DisableProgramGroupPage=yes
; Desinstalar es un procedimiento con respaldo previo (GUIA-INSTALACION.md, seccion 8), no un clic
Uninstallable=no
PrivilegesRequired=admin
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
MinVersion=10.0
OutputBaseFilename=Warique-Setup-{#AppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
SetupLogging=yes
CloseApplications=no
RestartIfNeededByRun=no

[Languages]
Name: "es"; MessagesFile: "compiler:Languages\Spanish.isl"

[InstallDelete]
; Solo el paquete anterior extraido aqui; los datos viven en MySQL y C:\Warique
Type: filesandordirs; Name: "{app}\*"

[Files]
Source: "{#PackageDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Run]
Filename: "http://localhost:3000"; Description: "Abrir Warique en el navegador"; Flags: postinstall shellexec skipifsilent nowait; Check: SetupSucceeded
Filename: "{win}\notepad.exe"; Parameters: """{app}\resultado.log"""; Description: "Ver el registro de la instalacion"; Flags: postinstall skipifsilent nowait; Check: SetupFailed

[Code]
const
  InstallRoot = 'C:\Warique';

var
  IsUpdate: Boolean;
  Succeeded: Boolean;
  FinishText: String;
  MySqlPage: TInputQueryWizardPage;
  OwnerPage: TInputQueryWizardPage;
  OptionsPage: TInputOptionWizardPage;

function SetEnvironmentVariable(lpName: String; lpValue: String): BOOL;
  external 'SetEnvironmentVariableW@kernel32.dll stdcall';

function MySqlServiceExists(): Boolean;
var
  Names: TArrayOfString;
  I: Integer;
begin
  Result := False;
  if RegGetSubkeyNames(HKLM, 'SYSTEM\CurrentControlSet\Services', Names) then
    for I := 0 to GetArrayLength(Names) - 1 do
      if Pos('MYSQL', Uppercase(Names[I])) = 1 then
      begin
        Result := True;
        Exit;
      end;
end;

function InitializeSetup(): Boolean;
begin
  Result := True;
  IsUpdate := FileExists(InstallRoot + '\config\deploy.json');
  if not MySqlServiceExists() then
  begin
    SuppressibleMsgBox('No se encontro MySQL en esta PC.' + #13#10#13#10 +
      'Instala primero MySQL 8.4 LTS como servicio de Windows (ver GUIA-INSTALACION.md, seccion 1) ' +
      'y vuelve a ejecutar este instalador.', mbCriticalError, MB_OK, IDOK);
    Result := False;
  end;
end;

procedure InitializeWizard();
var
  MySqlHelp: String;
begin
  if IsUpdate then
    MySqlHelp := 'Warique ya esta instalado: se actualizara a la version {#AppVersion}. Antes se hace un ' +
      'respaldo y, si la version nueva no arranca, vuelve sola a la anterior. La clave solo se usa si ' +
      'esta version trae cambios en la base de datos; no se guarda.'
  else
    MySqlHelp := 'La clave que elegiste al instalar MySQL 8.4. Solo se usa durante la instalacion; no se guarda.';
  MySqlPage := CreateInputQueryPage(wpWelcome, 'Base de datos', 'Clave del usuario root de MySQL', MySqlHelp);
  MySqlPage.Add('Clave de root:', True);

  OwnerPage := CreateInputQueryPage(MySqlPage.ID, 'Cuenta del dueno',
    'Con esta cuenta entraras a la app para crear el menu, las mesas y el personal',
    'Usuario en minusculas y sin espacios (ej.: dueno). Clave de 10 caracteres o mas.');
  OwnerPage.Add('Usuario:', False);
  OwnerPage.Add('Nombre completo:', False);
  OwnerPage.Add('Clave:', True);
  OwnerPage.Add('Repite la clave:', True);

  OptionsPage := CreateInputOptionPage(OwnerPage.ID, 'Opciones', 'Respaldos y red',
    'Marca lo que corresponda a esta PC:', False, False);
  OptionsPage.Add('Copiar los respaldos a Google Drive (Google Drive para escritorio en modo "Duplicar archivos")');
  OptionsPage.Add('Esta PC esta en la red del local: marcarla como red Privada para que los celulares se conecten');
  OptionsPage.Values[0] := True;
  OptionsPage.Values[1] := True;
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := IsUpdate and ((PageID = OwnerPage.ID) or (PageID = OptionsPage.ID));
end;

function ValidUsername(Value: String): Boolean;
var
  I: Integer;
begin
  Result := (Length(Value) >= 3) and (Length(Value) <= 50);
  for I := 1 to Length(Value) do
    if Pos(Copy(Value, I, 1), 'abcdefghijklmnopqrstuvwxyz0123456789._-') = 0 then
      Result := False;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if WizardSilent then
    Exit; // silent (CI): the secrets come from the environment
  if CurPageID = MySqlPage.ID then
  begin
    if MySqlPage.Values[0] = '' then
    begin
      MsgBox('Ingresa la clave de root de MySQL.', mbError, MB_OK);
      Result := False;
    end;
  end
  else if CurPageID = OwnerPage.ID then
  begin
    OwnerPage.Values[0] := Lowercase(Trim(OwnerPage.Values[0]));
    if not ValidUsername(OwnerPage.Values[0]) then
    begin
      MsgBox('Usuario: de 3 a 50 caracteres, solo minusculas, numeros, ".", "_" o "-".', mbError, MB_OK);
      Result := False;
    end
    else if (Trim(OwnerPage.Values[1]) = '') or (Length(OwnerPage.Values[1]) > 100) then
    begin
      MsgBox('Ingresa el nombre completo del dueno.', mbError, MB_OK);
      Result := False;
    end
    else if (Length(OwnerPage.Values[2]) < 10) or (Length(OwnerPage.Values[2]) > 72) then
    begin
      MsgBox('La clave debe tener entre 10 y 72 caracteres.', mbError, MB_OK);
      Result := False;
    end
    else if OwnerPage.Values[2] <> OwnerPage.Values[3] then
    begin
      MsgBox('Las claves no coinciden.', mbError, MB_OK);
      Result := False;
    end;
  end;
end;

procedure RunSetupScript();
var
  Params, ResultFile: String;
  Lines: TArrayOfString;
  ShowCmd, Code, I: Integer;
  UseDrive, MarkPrivate: Boolean;
begin
  ResultFile := ExpandConstant('{app}\resultado.txt');
  // Silent (CI): the secrets are already in this process' environment
  if not WizardSilent then
  begin
    SetEnvironmentVariable('WARIQUE_MYSQL_ADMIN_PASSWORD', MySqlPage.Values[0]);
    if not IsUpdate then
    begin
      SetEnvironmentVariable('OWNER_USERNAME', OwnerPage.Values[0]);
      SetEnvironmentVariable('OWNER_FULL_NAME', Trim(OwnerPage.Values[1]));
      SetEnvironmentVariable('OWNER_PASSWORD', OwnerPage.Values[2]);
    end;
    UseDrive := OptionsPage.Values[0];
    MarkPrivate := OptionsPage.Values[1];
    ShowCmd := SW_SHOWNORMAL; // the console shows the progress (and any question from the scripts)
  end
  else
  begin
    UseDrive := ExpandConstant('{param:GDRIVE|0}') = '1';
    MarkPrivate := ExpandConstant('{param:REDPRIVADA|0}') = '1';
    ShowCmd := SW_HIDE;
  end;

  Params := '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{app}\scripts\setup-run.ps1') +
    '" -ResultFile "' + ResultFile + '"';
  if IsUpdate then
    Params := Params + ' -Mode update'
  else
  begin
    Params := Params + ' -Mode install';
    if UseDrive then Params := Params + ' -GoogleDrive';
    if MarkPrivate then Params := Params + ' -MarkNetworkPrivate';
    if ExpandConstant('{param:MYSQLSERVICE|}') <> '' then
      Params := Params + ' -MySqlService "' + ExpandConstant('{param:MYSQLSERVICE|}') + '"';
  end;

  WizardForm.StatusLabel.Caption := 'Configurando Warique: base de datos, servicio y respaldo de prueba (unos minutos)...';
  if not Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), Params, ExpandConstant('{app}'),
    ShowCmd, ewWaitUntilTerminated, Code) then
    Code := -1;

  if not WizardSilent then
  begin
    SetEnvironmentVariable('WARIQUE_MYSQL_ADMIN_PASSWORD', '');
    SetEnvironmentVariable('OWNER_PASSWORD', '');
  end;

  // Nested on purpose: never index Lines unless it was loaded and has a first line
  Succeeded := False;
  if Code = 0 then
    if LoadStringsFromFile(ResultFile, Lines) then
      if GetArrayLength(Lines) > 0 then
        Succeeded := Trim(Lines[0]) = 'OK';
  if Succeeded then
  begin
    if IsUpdate then
      FinishText := 'Warique se actualizo a la version {#AppVersion}. Recarga la app en los celulares.'
    else
      FinishText := 'Warique quedo instalado y funcionando como servicio de Windows.';
    FinishText := FinishText + #13#10#13#10 + 'Abre la app desde los celulares conectados al Wi-Fi del local:';
    for I := 1 to GetArrayLength(Lines) - 1 do
      if Trim(Lines[I]) <> '' then
        FinishText := FinishText + #13#10 + '    ' + Trim(Lines[I]);
    FinishText := FinishText + #13#10#13#10 + 'Siguiente paso: la lista de puesta en marcha de GUIA-INSTALACION.md ' +
      '(menu, mesas, usuarios e insumos).';
  end
  else
    FinishText := 'La configuracion de Warique NO termino.' + #13#10#13#10 +
      'Revisa el registro (puedes abrirlo abajo): ' + ExpandConstant('{app}\resultado.log') + #13#10 +
      'Corrige lo indicado y vuelve a ejecutar este instalador. Si no sabes como, envia ese archivo a soporte.';
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
    RunSetupScript();
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = wpFinished then
  begin
    WizardForm.FinishedLabel.Caption := FinishText;
    WizardForm.AdjustLabelHeight(WizardForm.FinishedLabel);
  end;
end;

function SetupSucceeded(): Boolean;
begin
  Result := Succeeded;
end;

function SetupFailed(): Boolean;
begin
  Result := not Succeeded;
end;
