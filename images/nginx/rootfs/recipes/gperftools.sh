rm -rf build
mkdir build
cd build
cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=0 ..
make -j`nproc` VERBOSE=1
sudo make install