use Test::Class::Sugar;

testclass exercises DB::CouchDB {

    # Test::Most has been magically included
    # 'warnings' and 'strict' are turned on

    startup >> 1 {
        use_ok $test->subject;
      }

      test creating named documents >> 16 {
        lives_and {
            my $db;
            $db = $test->subject->new(
                host => 'localhost',
                db   => 'test DB::CouchDB'
            );
            isa_ok $db, $test->subject, 'db object created okay';

            my $rs;
            $rs = $db->create_db;
            isnt $rs->err, undef,
              'database creation should fail without uname, passwd';

            $ENV{CDB_USER} ||= '';
            $ENV{CDB_PASS} ||= '';
            $ENV{CDB_PORT} ||= 5984;
            $ENV{CDB_HOST} ||= 'localhost';

          SKIP: {
                if ( !$ENV{CDB_USER} || !$ENV{CDB_PASS} ) {
                    skip(
'DBI_DSN contains no database option, so skipping these tests',
                        14
                    );
                }

                $db = $test->subject->new(
                    host       => $ENV{CDB_HOST},
                    port       => $ENV{CDB_PORT},
                    db         => 'test DB::CouchDB',
                    'user'     => $ENV{CDB_USER},
                    'password' => $ENV{CDB_PASS},
                );
                isa_ok $db, $test->subject, 'db object created okay';

                $rs = $db->create_db;
                isnt $rs->err, undef,
                  'database creation should fail with bad db name';
                is $rs->errstr, 'Only lowercase characters (a-z), digits (0-9), and any of the characters _, $, (, ), +, -, and / are allowed',
                  'database creation should fail with bad db name';

                $db = $test->subject->new(
                    host       => $ENV{CDB_HOST},
                    port       => $ENV{CDB_PORT},
                    db         => 'test_DB_CouchDB',
                    'user'     => $ENV{CDB_USER},
                    'password' => $ENV{CDB_PASS}
                );
                is ref($db), $test->subject, 'db object created okay';
                isnt $rs->err, undef,
                  'database creation should fail with bad db name';
                is $rs->errstr, 'Only lowercase characters (a-z), digits (0-9), and any of the characters _, $, (, ), +, -, and / are allowed',
                  'database creation should fail with bad db name';

                $db = $test->subject->new(
                    host       => $ENV{CDB_HOST},
                    port       => $ENV{CDB_PORT},
                    db         => 'test_db_couchdb',
                    'user'     => $ENV{CDB_USER},
                    'password' => $ENV{CDB_PASS}
                );
                is ref($db), $test->subject, 'db object created okay';
                $rs = $db->create_db;
                is $rs->err, undef, 'database creation should succeed';

                # test creating a document
                my $doc = {
                    'banana' => 'pancakes',
                    'are' => [ 'not', 'my', 'favorite', { 'breakfast' => 1 }, ]
                };
                my $db_doc = $db->create_doc($doc);
                is $db_doc->{'are'}->[3]->{'breakfast'},
                  $db->{'are'}->[3]->{'breakfast'}, 'created a document';

                my $idlist = $db->all_docs();
                is $idlist->count, 1, 'expect one document stored in db';

                # check names with slashes
                $doc = {
                    '_id' => '/my/long/path/to/data/document.tgz',
                    'row' => 30
                };
                $db_doc = $db->create_named_doc( { 'doc' => $doc } );
                diag(
                    'response to create call is ',
                    Data::Dumper::Dumper($db_doc)
                );
                $db_doc = $db->get_doc( $doc->{'_id'} );
                diag(
                    'get named document response is ',
                    Data::Dumper::Dumper($db_doc)
                );
                is $db_doc->{'_id'}, $doc->{'_id'},
                  'check names with slashes are okay';

                # delete the test db

                $rs = $db->delete_db();

                isa_ok $rs, 'DB::CouchDB::Result',
                  'database deletion should pass here';
                is $rs->err, undef, 'database deletion should pass here';

            }

            END {
                if ( !$ENV{CDB_USER} || !$ENV{CDB_PASS} ) {
                    diag(
'live access tests not run due to missing username or password'
                    );
                }
                diag(   "environment vars used for testing CouchDB access\n"
                      . "CDB_USER          "
                      . $ENV{CDB_USER} . "\n"
                      . "CDB_PASS          "
                      . $ENV{CDB_PASS} . "\n"
                      . "CDB_PORT          "
                      . $ENV{CDB_PORT} . "\n"
                      . "CDB_HOST          "
                      . $ENV{CDB_HOST}
                      . "\n" );
            }

        };

      };
}

Test::Class->runtests unless caller;
