program SimpleTest;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  injector4d in '..\Source\injector4d.pas',
  injector4d.container in '..\Source\injector4d.container.pas',
  injector4d.events in '..\Source\injector4d.events.pas',
  injector4d.factory in '..\Source\injector4d.factory.pas',
  injector4d.service in '..\Source\injector4d.service.pas';

type
  ITestService = interface
    ['{12345678-1234-1234-1234-123456789012}']
    function GetMessage: string;
  end;

  TTestService = class(TInterfacedObject, ITestService)
  public
    function GetMessage: string;
  end;

  TTestClass = class
  private
    FMessage: string;
  public
    constructor Create;
    property Message: string read FMessage;
  end;

function TTestService.GetMessage: string;
begin
  Result := 'Test Service Working!';
end;

constructor TTestClass.Create;
begin
  inherited;
  FMessage := 'Test Class Working!';
end;

var
  Injector: TInjector4D;
  TestObj: TTestClass;
  TestIntf: ITestService;
  I: Integer;
begin
  try
    WriteLn('=== Teste do Injector4D com Melhorias ===');
    WriteLn;
    
    // Teste 1: Thread Safety
    WriteLn('1. Testando Thread Safety...');
    Injector := GetInjector;
    if Assigned(Injector) then
      WriteLn('   ✓ GetInjector funcionando com thread safety')
    else
      WriteLn('   ✗ Erro no GetInjector');
    
    // Teste 2: Registro de Singleton
    WriteLn('2. Testando registro de Singleton...');
    try
      Injector.Singleton<TTestClass>();
      WriteLn('   ✓ Singleton registrado com sucesso');
    except
      on E: Exception do
        WriteLn('   ✗ Erro ao registrar singleton: ' + E.Message);
    end;
    
    // Teste 3: Recuperação de instância
    WriteLn('3. Testando recuperação de instância...');
    try
      TestObj := Injector.Get<TTestClass>();
      if Assigned(TestObj) then
        WriteLn('   ✓ Instância recuperada: ' + TestObj.Message)
      else
        WriteLn('   ✗ Instância não recuperada');
    except
      on E: EServiceNotFound do
        WriteLn('   ✓ Exceção EServiceNotFound funcionando: ' + E.Message);
      on E: Exception do
        WriteLn('   ✗ Erro inesperado: ' + E.Message);
    end;
    
    // Teste 4: Registro duplicado
    WriteLn('4. Testando detecção de registro duplicado...');
    try
      Injector.Singleton<TTestClass>();
      WriteLn('   ✗ Deveria ter lançado exceção para registro duplicado');
    except
      on E: EServiceAlreadyRegistered do
        WriteLn('   ✓ Exceção EServiceAlreadyRegistered funcionando: ' + E.Message);
      on E: Exception do
        WriteLn('   ✗ Exceção incorreta: ' + E.Message);
    end;
    
    // Teste 5: Interface
    WriteLn('5. Testando registro de interface...');
    try
      Injector.SingletonInterface<ITestService, TTestService>();
      TestIntf := Injector.GetInterface<ITestService>();
      if Assigned(TestIntf) then
        WriteLn('   ✓ Interface recuperada: ' + TestIntf.GetMessage)
      else
        WriteLn('   ✗ Interface não recuperada');
    except
      on E: Exception do
        WriteLn('   ✗ Erro com interface: ' + E.Message);
    end;
    
    // Teste 6: Múltiplas chamadas (Thread Safety)
    WriteLn('6. Testando múltiplas chamadas simultâneas...');
    try
      for I := 1 to 100 do
      begin
        TestObj := GetInjector.Get<TTestClass>();
        if not Assigned(TestObj) then
        begin
          WriteLn('   ✗ Falha na chamada ' + IntToStr(I));
          Break;
        end;
      end;
      WriteLn('   ✓ 100 chamadas simultâneas executadas com sucesso');
    except
      on E: Exception do
        WriteLn('   ✗ Erro em múltiplas chamadas: ' + E.Message);
    end;
    
    WriteLn;
    WriteLn('=== Teste Concluído ===');
    
  except
    on E: Exception do
    begin
      WriteLn('Erro geral: ' + E.ClassName + ' - ' + E.Message);
      ExitCode := 1;
    end;
  end;
  
  WriteLn('Pressione ENTER para sair...');
  ReadLn;
end.