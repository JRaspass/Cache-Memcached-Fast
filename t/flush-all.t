use lib 't';

use Memd;
use Test2::Require::AuthorTesting;    # So we don't nuke users' cache.
use Test2::V0;

is $memd->flush_all, { '127.0.0.1:11211' => 1, 'localhost:11211' => 1 };

done_testing;
