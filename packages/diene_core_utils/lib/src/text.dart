library;

/// Case-insensitive substring test; an empty [needle] always matches.
bool fuzzyIncludes(String haystack, String needle) =>
    haystack.toLowerCase().contains(needle.toLowerCase());
