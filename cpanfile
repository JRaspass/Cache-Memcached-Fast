requires 'XSLoader';

on test => sub {
    requires 'Test::More' => '0.96';    # For subtest w/o plan.
};
