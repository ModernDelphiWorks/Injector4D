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

unit Injector.Service;

interface

uses
  System.Rtti,
  System.TypInfo,
  System.SysUtils,
  System.Generics.Collections,
  Injector4D.Events;

type
  TInjectionMode = (imSingleton, imFactory);
  TConstructorEvents = TObjectDictionary<String, TInjectorEvents>;

  TServiceData = class
  private
    FServiceClass: TClass;
    FInjectionMode: TInjectionMode;
    FInstance: TObject;
    FInterface: TValue;
    FGuid: TGUID;
    function _FactoryInstance<T: class>(const AInjectorEvents: TConstructorEvents;
      const AParams: TConstructorParams = nil): T;
    function _FactoryInterface<I: IInterface>(const AKey: String;
      const AInjectorEvents: TConstructorEvents;
      const AParams: TConstructorParams = nil): TValue;
    function _Factory(const AParams: TConstructorParams): TValue;
  public
    constructor Create(const AServiceClass: TClass;
      const AInstance: TObject;
      const AInjectionMode: TInjectionMode); overload;
    constructor CreateInterface(const AServiceClass: TClass;
      const AGuid: TGUID;
      const AInterface: TValue;
      const AInjectionMode: TInjectionMode); overload;
    destructor Destroy; override;
    function ServiceClass: TClass;
    function InjectionMode: TInjectionMode;
    function AsInstance: TObject; overload;
    function GetInstance<T: class>(
      const AInjectorEvents: TConstructorEvents;
      const AParams: TConstructorParams): T; overload;
    function GetInterface<I: IInterface>(const AKey: String;
      const AInjectorEvents: TConstructorEvents;
      const AParams: TConstructorParams): I;
  end;

implementation

constructor TServiceData.Create(const AServiceClass: TClass;
  const AInstance: TObject;
  const AInjectionMode: TInjectionMode);
begin
  FServiceClass := AServiceClass;
  FInstance := AInstance;
  FInjectionMode := AInjectionMode;
end;

constructor TServiceData.CreateInterface(const AServiceClass: TClass;
  const AGuid: TGuid;
  const AInterface: TValue;
  const AInjectionMode: TInjectionMode);
begin
  FServiceClass := AServiceClass;
  FGuid := AGuid;
  FInterface := AInterface;
  FInjectionMode := AInjectionMode;
end;

destructor TServiceData.Destroy;
begin
  FInterface := nil;
  if Assigned(FInstance) then
    FInstance.Free;
  inherited;
end;

function TServiceData._Factory(const AParams: TConstructorParams): TValue;
var
  LContext: TRttiContext;
  LTypeObject: TRttiType;
  LMetaClass: TClass;
  LConstructorMethod: TRttiMethod;
  LValue: TValue;
begin
  Result := nil;
  LContext := TRttiContext.Create;
  try
    LTypeObject := LContext.GetType(FServiceClass);
    LMetaClass := LTypeObject.AsInstance.MetaClassType;
    LConstructorMethod := LTypeObject.GetMethod('Create');
    LValue := LConstructorMethod.Invoke(LMetaClass, AParams);
    Result := LValue;
  finally
    LContext.Free;
  end;
end;

function TServiceData._FactoryInstance<T>(const AInjectorEvents: TConstructorEvents;
 const AParams: TConstructorParams): T;
var
  LResult: TValue;
  LOnCreate: TProc<T>;
  LOnParams: TFunc<TConstructorParams>;
  LResultParams: TConstructorParams;
begin
  Result := nil;
  LResultParams := [];
  if AInjectorEvents.ContainsKey(T.Classname) then
  begin
    LOnParams := TFunc<TConstructorParams>(AInjectorEvents.Items[T.ClassName].OnParams);
    if Assigned(LOnParams) then
      LResultParams := LOnParams();
  end
  else
  begin
    if Length(AParams) > 0 then
      LResultParams := AParams;
  end;
  LResult := _Factory(LResultParams);
  if not LResult.IsObjectInstance then
    Exit;
  Result := LResult.AsType<T>;
  // OnCreate
  if AInjectorEvents.ContainsKey(T.Classname) then
  begin
    LOnCreate := TProc<T>(AInjectorEvents.Items[T.ClassName].OnCreate);
    if Assigned(LOnCreate) then
      LOnCreate(Result);
  end;
end;

function TServiceData._FactoryInterface<I>(const AKey: String;
  const AInjectorEvents: TConstructorEvents;
  const AParams: TConstructorParams): TValue;
var
  LResult: TValue;
  LOnCreate: TProc<I>;
  LOnParams: TFunc<TConstructorParams>;
  LResultParams: TConstructorParams;
begin
  Result := nil;
  LResultParams := [];
  if AInjectorEvents.ContainsKey(AKey) then
  begin
    LOnParams := TFunc<TConstructorParams>(AInjectorEvents.Items[AKey].OnParams);
    if Assigned(LOnParams) then
      LResultParams := LOnParams();
  end
  else
  begin
    if Length(AParams) > 0 then
      LResultParams := AParams;
  end;
  LResult := _Factory(LResultParams);
  if not LResult.IsObjectInstance then
    Exit;
  // OnCreate
  if AInjectorEvents.ContainsKey(AKey) then
  begin
    LOnCreate := TProc<I>(AInjectorEvents.Items[AKey].OnCreate);
    if Assigned(LOnCreate) then
      LOnCreate(Result.AsType<I>);
  end;
  Result := LResult;
end;

function TServiceData.AsInstance: TObject;
begin
  Result := FInstance;
end;

function TServiceData.GetInstance<T>(const AInjectorEvents: TConstructorEvents;
  const AParams: TConstructorParams): T;
begin
  Result := nil;
  case FInjectionMode of
    imSingleton:
    begin
      if not Assigned(FInstance) then
        FInstance := _FactoryInstance<T>(AInjectorEvents, AParams);
      Result := FInstance as T;
    end;
    imFactory: Result := _FactoryInstance<T>(AInjectorEvents, AParams);
  end;
end;

function TServiceData.GetInterface<I>(const AKey: String;
  const AInjectorEvents: TConstructorEvents;
  const AParams: TConstructorParams): I;
begin
  if not FInterface.IsObjectInstance then
  begin
    try
      FInterface := _FactoryInterface<I>(AKey, AInjectorEvents, AParams);
    except
      FInterface := TValue.From(nil);
      raise;
    end;
  end;
  Result := FInterface.AsType<I>;
end;

function TServiceData.InjectionMode: TInjectionMode;
begin
  Result := FInjectionMode;
end;

function TServiceData.ServiceClass: TClass;
begin
  Result := FServiceClass;
end;

end.


