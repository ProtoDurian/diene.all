namespace AtomiCloud.DotnetBase.UnitTest.Meta;

public class VfsPathTests
{
    [Theory]
    [InlineData("/a/b", "/a/b")]
    [InlineData("a/b", "/a/b")]
    [InlineData("/a/b/", "/a/b")]
    [InlineData("//a//b//", "/a/b")]
    [InlineData("\\a\\b", "/a/b")]
    [InlineData("/", "/")]
    [InlineData("", "/")]
    [InlineData("   ", "/")]
    public void It_should_normalize_separators_and_trailing_slashes(string path, string expected)
    {
        // Act
        var normalized = VfsPath.Normalize(path);

        // Assert
        normalized.Should().Be(expected);
    }

    [Fact]
    public void It_should_reject_a_null_path()
    {
        // Act
        var act = () => VfsPath.Normalize(null!);

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void It_should_publish_the_root()
    {
        // Act
        var root = VfsPath.Root;

        // Assert
        root.Should().Be("/");
    }

    [Theory]
    [InlineData("/a/b/c", "/a/b")]
    [InlineData("/a", "/")]
    public void It_should_resolve_parents(string path, string expected)
    {
        // Act
        var parent = VfsPath.Parent(path);

        // Assert
        parent.Should().BeSome(expected);
    }

    [Fact]
    public void It_should_report_no_parent_at_the_root()
    {
        // Act
        var parent = VfsPath.Parent("/");

        // Assert
        parent.IsNone().Should().BeTrue();
    }

    [Theory]
    [InlineData("/a/b", "/a", true)]
    [InlineData("/a/b/c", "/a", true)]
    [InlineData("/a", "/a", false)]
    [InlineData("/ab", "/a", false)]
    [InlineData("/a", "/", true)]
    [InlineData("/", "/", false)]
    public void It_should_decide_descent(string candidate, string ancestor, bool expected)
    {
        // Act
        var below = VfsPath.IsBelow(candidate, ancestor);

        // Assert
        below.Should().Be(expected);
    }

    [Theory]
    [InlineData("/a/b", "/a", true)]
    [InlineData("/a/b/c", "/a", false)]
    [InlineData("/a", "/", true)]
    [InlineData("/a", "/a", false)]
    public void It_should_decide_direct_children(string candidate, string parent, bool expected)
    {
        // Act
        var child = VfsPath.IsDirectChild(candidate, parent);

        // Assert
        child.Should().Be(expected);
    }
}
