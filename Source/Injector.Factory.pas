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

unit Injector.Factory;

interface

uses
  System.Rtti,
  System.SysUtils,
  Injector4D.Service;

type
  TInjectorFactory = class
  private
    function _FactoryInternal(const Args: TArray<TValue>): TServiceData;
  public
    function FactorySingleton<T: class, constructor>(): TServiceData;
    function FactoryInterface<I: IInterface>(const AClass: TClass;
      const AGuid: TGUID): TServiceData;
    function Factory<T: class, constructor>(): TServiceData;
  end;

implementation

{ TInjectorFactory }

function TInjectorFactory.Factory<T>(): TServiceData;
var
  LArgs: TArray<TValue>;
begin
  SetLength(LArgs, 3);
  LArgs[0] := TValue.From<TClass>(T);
  LArgs[1] := TValue.From<TObject>(nil);
  LArgs[2] := TValue.From<TInjectionMode>(TInjectionMode.imFactory);
  Result := _FactoryInternal(LArgs);
end;

function TInjectorFactory.FactoryInterface<I>(const AClass: TClass;
  const AGuid: TGUID): TServiceData;
var
  LArgs: TArray<TValue>;
begin
  SetLength(LArgs, 4);
  LArgs[0] := TValue.From<TClass>(AClass);
  LArgs[1] := TValue.From<TGUID>(AGuid);
  LArgs[2] := TValue.From<TValue>(TValue.Empty);
  LArgs[3] := TValue.From<TInjectionMode>(TInjectionMode.imSingleton);
  Result := _FactoryInternal(LArgs);
end;

function TInjectorFactory.FactorySingleton<T>(): TServiceData;
var
  LArgs: TArray<TValue>;
begin
  SetLength(LArgs, 3);
  LArgs[0] := TValue.From<TClass>(T);
  LArgs[1] := TValue.From<TObject>(nil);
  LArgs[2] := TValue.From<TInjectionMode>(TInjectionMode.imSingleton);
  Result := _FactoryInternal(LArgs);
end;

function TInjectorFactory._FactoryInternal(const Args: TArray<TValue>): TServiceData;
var
  LContext: TRttiContext;
  LTypeService: TRttiType;
  LConstructorMethod: TRttiMethod;
  LInstance: TValue;
begin
  LContext := TRttiContext.Create;
  try
    LTypeService := LContext.GetType(TServiceData);
    if Length(Args) = 3 then
      LConstructorMethod := LTypeService.GetMethod('Create')
    else
      LConstructorMethod := LTypeService.GetMethod('CreateInterface');
    LInstance := LConstructorMethod.Invoke(LTypeService.AsInstance.MetaClassType, Args);
    Result := TServiceData(LInstance.AsObject);
  finally
    LContext.Free;
  end;
end;

end.
