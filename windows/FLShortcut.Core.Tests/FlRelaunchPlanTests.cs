using FLShortcut.Core.Organizer;
using Xunit;
using Step = FLShortcut.Core.Organizer.FlRelaunchPlan.Step;

namespace FLShortcut.Core.Tests;

/// 12/11 (« le bouton quitter et rouvrir… il ne rouvre pas automatiquement FL Studio ») : mêmes essais que le Mac
/// (FLRelaunchPlanTests.swift).
public class FlRelaunchPlanTests
{
    private static readonly int[] None = Array.Empty<int>();

    [Fact]
    public void FlIsLaunchedOnceItHasQuit()
    {
        var plan = new FlRelaunchPlan(oldPid: 10, now: 0);
        Assert.Equal(Step.Wait, plan.Next(1, new[] { 10 }));     // « Enregistrer ? » dans FL
        Assert.Equal(Step.Wait, plan.Next(3, new[] { 10 }));
        Assert.Equal(Step.Wait, plan.Next(3.5, None));           // parti : une seconde de battement
        Assert.Equal(Step.Launch, plan.Next(4.5, None));
        Assert.Equal(Step.Wait, plan.Next(5, None));             // le nouveau FL démarre
        Assert.Equal(Step.Done, plan.Next(6, new[] { 22 }));
        Assert.Equal(1, plan.Launches);
    }

    [Fact]
    public void FlReopenedByHandIsNotLaunchedAgain()
    {
        var plan = new FlRelaunchPlan(oldPid: 10, now: 0);
        Assert.Equal(Step.Wait, plan.Next(2, None));
        Assert.Equal(Step.Done, plan.Next(2.5, new[] { 30 }));
        Assert.Equal(0, plan.Launches);
    }

    [Fact]
    public void LaunchErrorIsRetriedSoon()
    {
        var plan = new FlRelaunchPlan(oldPid: 10, now: 0);
        Assert.Equal(Step.Wait, plan.Next(1, None));
        Assert.Equal(Step.Launch, plan.Next(2, None));
        plan.LaunchFailed(2);
        Assert.Equal(Step.Wait, plan.Next(3, None));
        Assert.Equal(Step.Launch, plan.Next(4, None));
        Assert.Equal(2, plan.Launches);
    }

    [Fact]
    public void FlThatNeverAppearsIsLaunchedThreeTimesThenLeft()
    {
        var plan = new FlRelaunchPlan(oldPid: 10, now: 0);
        Assert.Equal(Step.Wait, plan.Next(1, None));
        Assert.Equal(Step.Launch, plan.Next(2, None));
        Assert.Equal(Step.Wait, plan.Next(21.5, None));
        Assert.Equal(Step.Launch, plan.Next(22, None));
        Assert.Equal(Step.Launch, plan.Next(42, None));
        Assert.Equal(Step.GiveUp, plan.Next(62, None));
        Assert.Equal(FlRelaunchPlan.MaxLaunches, plan.Launches);
    }

    [Fact]
    public void FlThatStaysOpenIsLeftAfterFiveMinutes()
    {
        var plan = new FlRelaunchPlan(oldPid: 10, now: 0);
        Assert.Equal(Step.Wait, plan.Next(299, new[] { 10 }));   // « Annuler » à « Enregistrer ? »
        Assert.Equal(Step.GiveUp, plan.Next(300, new[] { 10 }));
        Assert.Equal(0, plan.Launches);
    }

    [Fact]
    public void ANewFlNextToTheOldOneCounts()
    {
        var plan = new FlRelaunchPlan(oldPid: 10, now: 0);
        Assert.Equal(Step.Done, plan.Next(1, new[] { 10, 31 }));
    }
}
