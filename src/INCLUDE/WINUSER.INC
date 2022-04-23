

ifdef __JWASM__
    option dllimport:<user32.dll>
endif

wsprintfA  proto C :ptr byte, :ptr byte, :vararg

ifdef __JWASM__
    option dllimport:none
endif

