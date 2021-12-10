set -ex

autoreconf -i -v || autoreconf -i -v
./configure
make -j`nproc`
sudo make install