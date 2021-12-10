rm -rf build
mkdir build
cd build
cmake ..
make -j`nproc` VERBOSE=1
sudo make install