use inc::Module::Install;

name 'DB-CouchDB-Schema';

requires 'JSON';
requires 'Getopt::Long';
requires 'LWP::UserAgent';
requires 'Moose'            => '0.57';
requires 'Carp';
requires 'URI';
requires 'Pod::Usage';
requires 'Term::ReadLine';

build_requires 'Test::Exception';
build_requires 'Test::More';
build_requires 'Test::Moose';
build_requires 'Test::Class::Sugar';
build_requires 'Image::Info';

all_from 'lib/DB/CouchDB/Schema.pm';

auto_install;
WriteAll;
