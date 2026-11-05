async function twice(int $value): Awaitable<int> {
  await RescheduleWaitHandle::create(0, 0);
  return $value * 2;
}

<<__EntryPoint>>
function main(): void {
  $sum = 0;
  for ($i = 0; $i < 10000; ++$i) {
    $sum += $i;
  }
  invariant($sum === 49995000, 'arithmetic failed');
  invariant(HH\Asio\join(twice(21)) === 42, 'async failed');
  invariant(vec[1, 2, 3][1] === 2, 'collection failed');
  invariant(json_decode('{"ok":true}', true)['ok'] === true, 'JSON failed');
  echo "HHVM smoke OK\n";
}
