// @generated by hh_manual
abstract class Animal {
  public abstract function greet(): string;
}

class Dog extends Animal {
  <<__Override>>
  public function greet(): string {
    return "woof!";
  }
}