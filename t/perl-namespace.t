use Test2::V0 -target => 'Cache::Memcached::Fast';

is [ keys %Cache::Memcached::Fast:: ] => bag {
    item $_ for qw(
        BEGIN CLONE DESTROY ISA VERSION __ANON__ bootstrap dl_load_flags

        _destroy _new _weaken

        disconnect_all enable_compress flush_all namespace new nowait_push
        retrieve server_versions store

        add         add_multi
        append   append_multi
        cas         cas_multi
        decr       decr_multi
        delete   delete_multi
        gat         gat_multi
        gats       gats_multi
        get         get_multi
        gets       gets_multi
        incr       incr_multi
        prepend prepend_multi
        remove
        replace replace_multi
        set         set_multi
        touch     touch_multi
    );

    end;
};

done_testing;
