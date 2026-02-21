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

unit Injector.Container;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Injector4D.Factory,
  Injector4D.Service,
  Injector4D.Events;

type
  TInjectorAbstract = class
  end;

  TInjectorContainer = class(TInjectorAbstract)
  protected
    FInjectorFactory: TInjectorFactory;
    FRepositoryReference: TDictionary<String, TClass>;
    FRepositoryInterface: TDictionary<String, TPair<TClass, TGUID>>;
    FInstances: TObjectDictionary<String, TServiceData>;
    FInjectorEvents: TConstructorEvents;
  public
    constructor Create; virtual;
    destructor Destroy; override;
  end;

implementation

{ TInjectorFactory }

constructor TInjectorContainer.Create;
begin
  FInjectorFactory := TInjectorFactory.Create;
  FRepositoryReference := TDictionary<String, TClass>.Create;
  FRepositoryInterface := TDictionary<String, TPair<TClass, TGUID>>.Create;
  FInstances := TObjectDictionary<String, TServiceData>.Create([doOwnsValues]);
  FInjectorEvents := TConstructorEvents.Create([doOwnsValues]);
end;

destructor TInjectorContainer.Destroy;
begin
  FRepositoryReference.Free;
  FRepositoryInterface.Free;
  FInjectorEvents.Free;
  FInjectorFactory.Free;
  FInstances.Free;
  inherited;
end;

end.


