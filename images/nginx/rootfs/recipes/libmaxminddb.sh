git submodule update --init

autoreconf -i -v || autoreconf -i -v
./configure
make -j`nproc` SHELL="sh -x"
sudo make install