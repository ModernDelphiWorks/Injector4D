{
                          Apache License
                      Version 2.0, January 2004
                   http://www.apache.org/licenses/

       Licensed under the Apache License, Version 2.0 (the "License");
       you may not use this file except in compliance with the License.
       You may obtain a copy of the License at

             http://www.apache.org/licenses/LICENSE-2.0

       Unless required by applicable law or agreed to in writing, software
       distributed under the License is distributed on an "AS IS" BASIS,
       WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
       See the License for the specific language governing permissions and
       limitations under the License.
}

{
  @abstract(Injector4D - Dependency Injection for Delphi)
  @description(Evolution4D brings modern, fluent, and expressive syntax to Delphi, making code cleaner and development more productive.)
  @created(03 Abr 2023)
  @author(Isaque Pinheiro <isaquepsp@gmail.com>)
  @discord(https://discord.gg/T2zJC8zX)
}

unit Injector;

interface

uses
  System.Rtti,
  System.TypInfo,
  System.SysUtils,
  System.SyncObjs,
  System.Generics.Collections,
  Injector4d.Service,
  Injector4d.Container,
  Injector4d.Events;

type
  // Exceções específicas do Injector4D
  EInjectorException = class(Exception);
  EServiceAlreadyRegistered = class(EInjectorException);
  EServiceNotFound = class(EInjectorException);
  ECircularDependency = class(EInjectorException);
  TConstructorParams = injector4d.events.TConstructorParams;

  PInjector4D = ^TInjector4D;
  TInjector4D = class(TInjectorContainer)
  strict private
    FDependencyStack: TList<String>;
    // Cache RTTI para melhorar performance
    FRttiContext: TRttiContext;
    FTypeCache: TDictionary<String, TRttiType>;
    FMethodCache: TDictionary<String, TRttiMethod>;
    FRttiCacheLock: TCriticalSection;
    // Sistema de logging opcional
    FLoggingEnabled: Boolean;
    FLogCallback: TProc<String>;
    procedure _AddEvents<T>(const AClassName: String;
      const AOnCreate: TProc<T>;
      const AOnDestroy: TProc<T>;
      const AOnConstructorParams: TConstructorCallback = nil);
    function _ResolverInterfaceType(const AHandle: PTypeInfo;
      const AGUID: TGUID): TValue;
    function _ResolverParams(const AClass: TClass): TConstructorParams; overload;
    procedure _CheckCircularDependency(const AServiceName: String);
    procedure _PushDependency(const AServiceName: String);
    procedure _PopDependency;
    // Métodos de cache RTTI
    function _GetCachedType(const AClassName: String): TRttiType;
    function _GetCachedMethod(const AClassName, AMethodName: String): TRttiMethod;
    procedure _ClearRttiCache;
    // Métodos de logging
    procedure _Log(const AMessage: String);
    procedure _LogOperation(const AOperation, AServiceName: String);
  protected
    function GetTry<T: class, constructor>(const ATag: String = ''): T;
    function GetInterfaceTry<I: IInterface>(const ATag: String = ''): I;
  public
    constructor Create; override;
    destructor Destroy; override;
    procedure AddInjector(const ATag: String;
      const AInstance: TInjector4D);
    procedure AddInstance<T: class>(const AInstance: TObject);
//    procedure Singleton<T: class, constructor>(
//      const ATag: String = '';
//      const AOnCreate: TProc<T> = nil;
//      const AOnDestroy: TProc<T> = nil;
//      const AOnConstructorParams: TConstructorCallback = nil);
    procedure Singleton<T: class, constructor>(
      const AOnCreate: TProc<T> = nil;
      const AOnDestroy: TProc<T> = nil;
      const AOnConstructorParams: TConstructorCallback = nil); overload;
    procedure SingletonLazy<T: class>(
      const AOnCreate: TProc<T> = nil;
      const AOnDestroy: TProc<T> = nil;
      const AOnConstructorParams: TConstructorCallback = nil);
    procedure SingletonInterface<I: IInterface; T: class, constructor>(
      const ATag: String = '';
      const AOnCreate: TProc<T> = nil;
      const AOnDestroy: TProc<T> = nil;
      const AOnConstructorParams: TConstructorCallback = nil);
    procedure Factory<T: class, constructor>(
      const AOnCreate: TProc<T> = nil;
      const AOnDestroy: TProc<T> = nil;
      const AOnConstructorParams: TConstructorCallback = nil);
    procedure Remove<T: class>(const ATag: String = '');
    function GetInstances: TObjectDictionary<String, TServiceData>;
    function Get<T: class, constructor>(const ATag: String = ''): T;
    function GetInterface<I: IInterface>(const ATag: String = ''): I;
    // Métodos de logging público
    procedure EnableLogging(const ALogCallback: TProc<String> = nil);
    procedure DisableLogging;
    procedure ClearCache;
  end;

function GetInjector: TInjector4D;

var
  GPInjector: PInjector4D = nil;
  GInjectorLock: TCriticalSection = nil;

implementation

{ TInjectorBr }

constructor TInjector4D.Create;
begin
  inherited Create;
  FDependencyStack := TList<String>.Create;
  // Inicializar cache RTTI
  FRttiContext := TRttiContext.Create;
  FTypeCache := TDictionary<String, TRttiType>.Create;
  FMethodCache := TDictionary<String, TRttiMethod>.Create;
  FRttiCacheLock := TCriticalSection.Create;
  // Inicializar logging
  FLoggingEnabled := False;
  FLogCallback := nil;
end;

destructor TInjector4D.Destroy;
begin
  if Assigned(FDependencyStack) then
    FDependencyStack.Free;
  // Liberar cache RTTI
  if Assigned(FRttiCacheLock) then
    FRttiCacheLock.Free;
  if Assigned(FMethodCache) then
    FMethodCache.Free;
  if Assigned(FTypeCache) then
    FTypeCache.Free;
  FRttiContext.Free;
  inherited Destroy;
end;

function GetInjector: TInjector4D;
begin
  if not Assigned(GInjectorLock) then
    Exit(nil);
  GInjectorLock.Enter;
  try
    if Assigned(GPInjector) then
      Result := GPInjector^
    else
      Result := nil;
  finally
    GInjectorLock.Leave;
  end;
end;

procedure TInjector4D.Singleton<T>(const AOnCreate: TProc<T>;
  const AOnDestroy: TProc<T>;
  const AOnConstructorParams: TConstructorCallback);
var
  LValue: TServiceData;
  LKey: String;
begin
  LKey := T.ClassName;
  _LogOperation('Add Singleton', LKey);
  if FRepositoryReference.ContainsKey(LKey) then
    raise Exception.Create(Format('Class %s registered!', [LKey]));
  FRepositoryReference.Add(LKey, TServiceData);
  // Singleton
  LValue := FInjectorFactory.FactorySingleton<T>();
  FInstances.Add(LKey, LValue);
  // Events
  _AddEvents<T>(LKey, AOnCreate, AOnDestroy, AOnConstructorParams);
end;

procedure TInjector4D.SingletonInterface<I, T>(const ATag: String;
  const AOnCreate: TProc<T>;
  const AOnDestroy: TProc<T>;
  const AOnConstructorParams: TConstructorCallback);
var
  LGuid: TGUID;
  LGuidString: String;
begin
  LGuid := GetTypeData(TypeInfo(I)).Guid;
  LGuidString := GUIDToString(LGuid);
  if ATag <> '' then
    LGuidString := ATag;
  if FRepositoryInterface.ContainsKey(LGuidString) then
    raise EServiceAlreadyRegistered.Create(Format('Interface %s already registered!', [T.ClassName]));
  FRepositoryInterface.Add(LGuidString, TPair<TClass, TGUID>.Create(T, LGuid));
  // Events
  _AddEvents<T>(LGuidString, AOnCreate, AOnDestroy, AOnConstructorParams);
end;

procedure TInjector4D.SingletonLazy<T>(const AOnCreate: TProc<T>;
  const AOnDestroy: TProc<T>;
  const AOnConstructorParams: TConstructorCallback);
begin
  if FRepositoryReference.ContainsKey(T.ClassName) then
    raise EServiceAlreadyRegistered.Create(Format('Class %s already registered!', [T.ClassName]));
  FRepositoryReference.Add(T.ClassName, TServiceData);
  // Events
  _AddEvents<T>(T.ClassName, AOnCreate, AOnDestroy, AOnConstructorParams);
end;

procedure TInjector4D.AddInjector(const ATag: String;
  const AInstance: TInjector4D);
var
  LValue: TServiceData;
begin
  if FRepositoryReference.ContainsKey(ATag) then
    raise EServiceAlreadyRegistered.Create(Format('Injector %s already registered!', [ATag]));
  FRepositoryReference.Add(ATag, TServiceData);
  LValue := TServiceData.Create(TInjector4D,
                                AInstance,
                                TInjectionMode.imSingleton);
  FInstances.Add(ATag, LValue);
end;

procedure TInjector4D.AddInstance<T>(const AInstance: TObject);
var
  LValue: TServiceData;
begin
  if FRepositoryReference.ContainsKey(T.ClassName) then
    raise EServiceAlreadyRegistered.Create(Format('Instance %s already registered!', [AInstance.ClassName]));
  FRepositoryReference.Add(T.ClassName, TServiceData);
  // Factory
  LValue := TServiceData.Create(T, AInstance, TInjectionMode.imSingleton);
  FInstances.Add(T.ClassName, LValue);
end;

procedure TInjector4D.Factory<T>(const AOnCreate: TProc<T>;
  const AOnDestroy: TProc<T>;
  const AOnConstructorParams: TConstructorCallback);
var
  LValue: TServiceData;
begin
  _LogOperation('Add Factory', T.ClassName);
  if FRepositoryReference.ContainsKey(T.ClassName) then
    raise Exception.Create(Format('Class %s registered!', [T.ClassName]));
  FRepositoryReference.Add(T.ClassName, TServiceData);
  // Factory
  LValue := FInjectorFactory.Factory<T>();
  FInstances.Add(T.ClassName, LValue);
  // Events
  _AddEvents<T>(T.ClassName, AOnCreate, AOnDestroy, AOnConstructorParams);
end;

function TInjector4D.GetInstances: TObjectDictionary<String, TServiceData>;
begin
  Result := FInstances;
end;

function TInjector4D.Get<T>(const ATag: String): T;
var
  LItem: TServiceData;
  LTag: String;
begin
  LTag := ATag;
  if LTag = '' then
    LTag := T.ClassName;
  _LogOperation('Get Service', LTag);
  
  Result := GetTry<T>(ATag);
  if Result <> nil then
  begin
    _Log('Service resolved: ' + LTag);
    Exit;
  end;
  
  for LItem in GetInstances.Values do
  begin
    if LItem.AsInstance is TInjector4D then
    begin
      Result := TInjector4D(LItem.AsInstance).GetTry<T>(ATag);
      if Result <> nil then
      begin
        _Log('Service resolved from child injector: ' + LTag);
        Exit;
      end;
    end;
  end;
  
  // Se chegou até aqui, o serviço não foi encontrado
  _Log('Service not found: ' + LTag);
  raise EServiceNotFound.Create(Format('Service %s not found!', [LTag]));
end;

function TInjector4D.GetInterface<I>(const ATag: String): I;
var
  LItem: TServiceData;
  LGuid: TGUID;
  LGuidString: String;
begin
  LGuid := GetTypeData(TypeInfo(I)).Guid;
  LGuidString := GUIDToString(LGuid);
  if ATag <> '' then
    LGuidString := ATag;
  _LogOperation('Get Interface', LGuidString);
  
  Result := GetInterfaceTry<I>(ATag);
  if Result <> nil then
  begin
    _Log('Interface resolved: ' + LGuidString);
    Exit;
  end;
  
  for LItem in GetInstances.Values do
  begin
    if LItem.AsInstance is TInjector4D then
    begin
      Result := TInjector4D(LItem.AsInstance).GetInterfaceTry<I>(ATag);
      if Result <> nil then
      begin
        _Log('Interface resolved from child injector: ' + LGuidString);
        Exit;
      end;
    end;
  end;
  
  // Se chegou até aqui, a interface não foi encontrada
  _Log('Interface not found: ' + LGuidString);
  raise EServiceNotFound.Create(Format('Interface %s not found!', [LGuidString]));
end;

function TInjector4D.GetTry<T>(const ATag: String): T;
var
  LValue: TServiceData;
  LParams: TConstructorParams;
  LTag: String;
begin
  Result := nil;
  LTag := ATag;
  if LTag = '' then
    LTag := T.ClassName;
  if not FRepositoryReference.ContainsKey(LTag) then
    Exit;
  
  // Verificar dependência circular
  _PushDependency(LTag);
  try
    // Lazy
    LParams := [];
    if not FInstances.ContainsKey(LTag) then
    begin
      LValue := FInjectorFactory.FactorySingleton<T>;
      FInstances.Add(LTag, LValue);
    end;
    if (FInstances.Items[LTag].AsInstance = nil) and (FInjectorEvents.Count = 0) then
      LParams := _ResolverParams(FInstances.Items[LTag].ServiceClass);
    Result := FInstances.Items[LTag].GetInstance<T>(FInjectorEvents, LParams);
  finally
    _PopDependency;
  end;
end;

function TInjector4D.GetInterfaceTry<I>(const ATag: String): I;
var
  LServiceData: TServiceData;
  LParams: TConstructorParams;
  LGuid: TGUID;
  LGuidString: String;
  LKey: TClass;
  LValue: TGUID;
begin
  Result := nil;
  LGuid := GetTypeData(TypeInfo(I)).Guid;
  LGuidString := GUIDToString(LGuid);
  if ATag <> '' then
    LGuidString := ATag;
  if not FRepositoryInterface.ContainsKey(LGuidString) then
    Exit;
  
  // Verificar dependência circular
  _PushDependency(LGuidString);
  try
    // SingletonLazy
    LParams := [];
    if not FInstances.ContainsKey(LGuidString) then
    begin
      LKey := FRepositoryInterface.Items[LGuidString].Key;
      LValue := FRepositoryInterface.Items[LGuidString].Value;
      LServiceData := FInjectorFactory.FactoryInterface<I>(LKey, LValue);
      FInstances.Add(LGuidString, LServiceData);
    end;
    if (FInstances.Items[LGuidString].AsInstance = nil) and (FInjectorEvents.Count = 0) then
      LParams := _ResolverParams(FInstances.Items[LGuidString].ServiceClass);
    Result := FInstances.Items[LGuidString].GetInterface<I>(LGuidString, FInjectorEvents, LParams);
  finally
    _PopDependency;
  end;
end;

procedure TInjector4D.Remove<T>(const ATag: String);
var
  LTag: String;
  LOnDestroy: TProc<T>;
begin
  LTag := ATag;
  if LTag = '' then
    LTag := T.ClassName;
  // OnDestroy
  if FInjectorEvents.ContainsKey(LTag) then
  begin
    LOnDestroy := TProc<T>(FInjectorEvents.Items[LTag].OnDestroy);
    if Assigned(LOnDestroy) then
      LOnDestroy(T(FInstances.Items[LTag].AsInstance));
  end;
  if FRepositoryReference.ContainsKey(LTag) then
    FRepositoryReference.Remove(LTag);
  if FRepositoryInterface.ContainsKey(LTag) then
    FRepositoryInterface.Remove(LTag);
  if FInjectorEvents.ContainsKey(LTag) then
    FInjectorEvents.Remove(LTag);
  if FInstances.ContainsKey(LTag) then
    FInstances.Remove(LTag);
end;

procedure TInjector4D._AddEvents<T>(const AClassName: String;
  const AOnCreate: TProc<T>;
  const AOnDestroy: TProc<T>;
  const AOnConstructorParams: TConstructorCallback);
var
  LEvents: TInjectorEvents;
begin
  if (not Assigned(AOnDestroy)) and (not Assigned(AOnCreate)) and
     (not Assigned(AOnConstructorParams)) then
    Exit;
  if FInjectorEvents.ContainsKey(AClassname) then
    Exit;
  LEvents := TInjectorEvents.Create;
  LEvents.OnDestroy := TProc<TObject>(AOnDestroy);
  LEvents.OnCreate := TProc<TObject>(AOnCreate);
  LEvents.OnParams := AOnConstructorParams;
  //
  FInjectorEvents.AddOrSetValue(AClassname, LEvents);
end;

function TInjector4D._ResolverParams(const AClass: TClass): TConstructorParams;

  function ToStringParams(const AValues: TArray<TValue>): String;
  var
    LIndex: Integer;
  begin
    Result := '';
    for LIndex := 0 to High(AValues) do
    begin
      Result := Result + AValues[LIndex].ToString;
      if LIndex < High(AValues) then
        Result := Result + ', ';
    end;
  end;

var
  LRttiType: TRttiType;
  LRttiMethod: TRttiMethod;
  LParameter: TRttiParameter;
  LParameterType: TRttiType;
  LInterfaceType: TRttiInterfaceType;
  LParameters: TArray<TRttiParameter>;
  LParameterValues: TArray<TValue>;
  LFor: Integer;
begin
  Result := [];
  // Usar cache RTTI para melhor performance
  LRttiType := _GetCachedType(AClass.ClassName);
  if not Assigned(LRttiType) then
    exit;
  LRttiMethod := _GetCachedMethod(AClass.ClassName, 'Create');
  if not Assigned(LRttiMethod) then
    exit;
  LParameters := LRttiMethod.GetParameters;
  SetLength(LParameterValues, Length(LParameters));
  try
    for LFor := 0 to High(LParameters) do
    begin
      LParameter := LParameters[LFor];
      LParameterType := LParameter.ParamType;
      case LParameterType.TypeKind of
        tkClass, tkClassRef:
        begin
          LParameterValues[LFor] := TValue.From(Get<TObject>(String(LParameterType.Handle.Name)))
                                          .Cast(LParameterType.Handle);
        end;
        tkInterface:
        begin
          LInterfaceType := FRttiContext.GetType(LParameterType.Handle) as TRttiInterfaceType;
          LParameterValues[LFor] := _ResolverInterfaceType(LParameterType.Handle,
                                                           LInterfaceType.GUID);
        end;
        else
          LParameterValues[LFor] := TValue.From(nil);
      end;
    end;
  except
    on E: Exception do
      raise Exception.Create(E.Message + ' => ' + ToStringParams(LParameterValues));
  end;
  Result := LParameterValues;
end;

function TInjector4D._ResolverInterfaceType(const AHandle: PTypeInfo;
  const AGUID: TGUID): TValue;
var
  LValue: TValue;
  LResult: TValue;
  LInterface: IInterface;
begin
  Result := TValue.From(nil);
  LValue := TValue.From(GetInterface<IInterface>(GUIDToString(AGUID)));
  if Supports(LValue.AsInterface, AGUID, LInterface) then
  begin
    TValue.Make(@LInterface, AHandle, LResult);
    Result := LResult;
  end;
end;

procedure TInjector4D._CheckCircularDependency(const AServiceName: String);
var
  LFor: Integer;
  LDep: Integer;
  LDependencyChain: String;
begin
  if not Assigned(FDependencyStack) then
    Exit;

  // Check if the service already exists in the dependency stack
  for LFor := 0 to FDependencyStack.Count - 1 do
  begin
    if FDependencyStack[LFor] = AServiceName then
    begin
      // Build the dependency chain for the error message, only up to the detected cycle
      LDependencyChain := '';
      for LDep := 0 to LFor do
      begin
        LDependencyChain := LDependencyChain + FDependencyStack[LDep];
        if LDep < LFor then
          LDependencyChain := LDependencyChain + ' -> ';
      end;
      // Add the current service again to close the cycle
      LDependencyChain := LDependencyChain + ' -> ' + AServiceName;

      raise ECircularDependency.Create(
        Format('Circular dependency detected: %s', [LDependencyChain])
      );
    end;
  end;
end;

procedure TInjector4D._PushDependency(const AServiceName: String);
begin
  if not Assigned(FDependencyStack) then
    FDependencyStack := TList<String>.Create;
  
  _CheckCircularDependency(AServiceName);
  FDependencyStack.Add(AServiceName);
end;

procedure TInjector4D._PopDependency;
begin
  if Assigned(FDependencyStack) and (FDependencyStack.Count > 0) then
    FDependencyStack.Delete(FDependencyStack.Count - 1);
end;

function TInjector4D._GetCachedType(const AClassName: String): TRttiType;
begin
  Result := nil;
  if not Assigned(FRttiCacheLock) then
    Exit;
  
  FRttiCacheLock.Enter;
  try
    if FTypeCache.ContainsKey(AClassName) then
      Result := FTypeCache[AClassName]
    else
    begin
      Result := FRttiContext.FindType(AClassName);
      if Assigned(Result) then
        FTypeCache.Add(AClassName, Result);
    end;
  finally
    FRttiCacheLock.Leave;
  end;
end;

function TInjector4D._GetCachedMethod(const AClassName, AMethodName: String): TRttiMethod;
var
  LKey: String;
  LRttiType: TRttiType;
begin
  Result := nil;
  if not Assigned(FRttiCacheLock) then
    Exit;
  
  LKey := AClassName + '.' + AMethodName;
  FRttiCacheLock.Enter;
  try
    if FMethodCache.ContainsKey(LKey) then
      Result := FMethodCache[LKey]
    else
    begin
      LRttiType := _GetCachedType(AClassName);
      if Assigned(LRttiType) then
      begin
        Result := LRttiType.GetMethod(AMethodName);
        if Assigned(Result) then
          FMethodCache.Add(LKey, Result);
      end;
    end;
  finally
    FRttiCacheLock.Leave;
  end;
end;

procedure TInjector4D._ClearRttiCache;
begin
  if not Assigned(FRttiCacheLock) then
    Exit;
  
  FRttiCacheLock.Enter;
  try
    if Assigned(FTypeCache) then
      FTypeCache.Clear;
    if Assigned(FMethodCache) then
      FMethodCache.Clear;
  finally
    FRttiCacheLock.Leave;
  end;
end;

procedure TInjector4D._Log(const AMessage: String);
begin
  if FLoggingEnabled and Assigned(FLogCallback) then
    FLogCallback(Format('[Injector4D] %s - %s', [FormatDateTime('hh:nn:ss.zzz', Now), AMessage]));
end;

procedure TInjector4D._LogOperation(const AOperation, AServiceName: String);
begin
  if FLoggingEnabled then
    _Log(Format('%s: %s', [AOperation, AServiceName]));
end;

procedure TInjector4D.EnableLogging(const ALogCallback: TProc<String>);
begin
  FLoggingEnabled := True;
  FLogCallback := ALogCallback;
  _Log('Logging enabled');
end;

procedure TInjector4D.DisableLogging;
begin
  if FLoggingEnabled then
    _Log('Logging disabled');
  FLoggingEnabled := False;
  FLogCallback := nil;
end;

procedure TInjector4D.ClearCache;
begin
  _Log('Clearing RTTI cache');
  _ClearRttiCache;
end;

initialization
  GInjectorLock := TCriticalSection.Create;
  New(GPInjector);
  GPInjector^ := TInjector4D.Create;

finalization
  if Assigned(GInjectorLock) then
  begin
    GInjectorLock.Enter;
    try
      if Assigned(GPInjector) then
      begin
        GPInjector^.Free;
        Dispose(GPInjector);
        GPInjector := nil;
      end;
    finally
      GInjectorLock.Leave;
      GInjectorLock.Free;
      GInjectorLock := nil;
    end;
  end;

end.


