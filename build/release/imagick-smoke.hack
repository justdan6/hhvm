<<__EntryPoint>>
function main(): void {
  $image = new Imagick();
  $image->newImage(4, 4, new ImagickPixel('red'));
  $image->setImageFormat('png');
  invariant(strlen($image->getImageBlob()) > 8, 'PNG encoding failed');
  echo "Imagick PNG smoke OK\n";
}
