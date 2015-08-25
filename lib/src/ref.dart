library  a_la_carte.server.ref;

class Ref<T> {
  T value;
  Ref();
  Ref.withValue(T this.value);
}