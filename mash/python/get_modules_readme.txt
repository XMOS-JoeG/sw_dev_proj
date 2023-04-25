How to install the required python modules a script requires:

You can use pipreqs to automatically generate a requirements.txt file based on the import statements that the Python script(s) contain.

To use pipreqs, assuming that you are in the directory where example.py is located:

pip install pipreqs
pipreqs .

It will generate a requirements.txt file (example):

matplotlib==3.7.1
numpy==1.24.2

which you can install with:

pip install -r requirements.txt