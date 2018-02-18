import itertools
import numpy as np
from numpy.testing import (assert_array_equal, assert_equal,
                           assert_array_almost_equal, run_module_suite)

from dipy.segment.clustering import QuickBundlesX
from dipy.segment.featurespeed import ResampleFeature
from dipy.segment.metric import AveragePointwiseEuclideanMetric
from dipy.tracking.streamline import set_number_of_points
from dipy.data import get_data
import nibabel.trackvis as tv


def straight_bundle(nb_streamlines=1, nb_pts=30, step_size=1,
                    radius=1, rng=np.random.RandomState(42)):
    bundle = []

    bundle_length = step_size * nb_pts

    Z = -np.linspace(0, bundle_length, nb_pts)
    for k in range(nb_streamlines):
        theta = rng.rand() * (2*np.pi)
        r = radius * rng.rand()

        Xk = np.ones(nb_pts) * (r * np.cos(theta))
        Yk = np.ones(nb_pts) * (r * np.sin(theta))
        Zk = Z.copy()

        bundle.append(np.c_[Xk, Yk, Zk])

    return bundle


def bearing_bundles(nb_balls=6, bearing_radius=2):
    bundles = []

    for theta in np.linspace(0, 2*np.pi, nb_balls, endpoint=False):
        x = bearing_radius * np.cos(theta)
        y = bearing_radius * np.sin(theta)

        bundle = np.array(straight_bundle(nb_streamlines=100))
        bundle += (x, y, 0)
        bundles.append(bundle)

    return bundles


def streamlines_in_circle(nb_streamlines=1, nb_pts=30, step_size=1,
                          radius=1):
    bundle = []

    bundle_length = step_size * nb_pts

    Z = np.linspace(0, bundle_length, nb_pts)
    theta = 0
    for theta in np.linspace(0, 2*np.pi, nb_streamlines, endpoint=False):
        Xk = np.ones(nb_pts) * (radius * np.cos(theta))
        Yk = np.ones(nb_pts) * (radius * np.sin(theta))
        Zk = Z.copy()

        bundle.append(np.c_[Xk, Yk, Zk])

    return bundle


def streamlines_parallel(nb_streamlines=1, nb_pts=30, step_size=1,
                         delta=1):
    bundle = []

    bundle_length = step_size * nb_pts

    Z = np.linspace(0, bundle_length, nb_pts)
    for x in delta*np.arange(0, nb_streamlines):
        Xk = np.ones(nb_pts) * x
        Yk = np.zeros(nb_pts)
        Zk = Z.copy()

        bundle.append(np.c_[Xk, Yk, Zk])

    return bundle


def simulated_bundle(no_streamlines=10, waves=False, no_pts=12):
    t = np.linspace(-10, 10, 200)
    # parallel waves or parallel lines
    bundle = []
    for i in np.linspace(-5, 5, no_streamlines):
        if waves:
            pts = np.vstack((np.cos(t), t, i * np.ones(t.shape))).T
        else:
            pts = np.vstack((np.zeros(t.shape), t, i * np.ones(t.shape))).T
        pts = set_number_of_points(pts, no_pts)
        bundle.append(pts)

    return bundle


def fornix_streamlines(no_pts=12):
    fname = get_data('fornix')
    streams, hdr = tv.read(fname)
    streamlines = [set_number_of_points(i[0], no_pts) for i in streams]
    return streamlines


def test_3D_points():

    points = np.array([[[1, 0, 0]],
                       [[3, 0, 0]],
                       [[2, 0, 0]],
                       [[5, 0, 0]],
                       [[5.5, 0, 0]]], dtype="f4")

    thresholds = [4, 2, 1]
    metric = AveragePointwiseEuclideanMetric()
    qbx_model = QuickBundlesX(thresholds,
                              metric=metric)
    qbx = qbx_model.cluster(points)
    clusters_2 = qbx.get_clusters(2)
    assert_array_equal(clusters_2.clusters_sizes(), [3, 2])
    clusters_0 = qbx.get_clusters(0)
    assert_array_equal(clusters_0.clusters_sizes(), [5])
    

def test_3D_segments():
    points = np.array([[[1, 0, 0],
                        [1, 1, 0]],
                       [[3, 1, 0],
                        [3, 0, 0]],
                       [[2, 0, 0],
                        [2, 1, 0]],
                       [[5, 1, 0],
                        [5, 0, 0]],
                       [[5.5, 0, 0],
                        [5.5, 1, 0]]], dtype="f4")

    thresholds = [4, 2, 1]
    
    feature = ResampleFeature(nb_points=20)
    metric = AveragePointwiseEuclideanMetric(feature)
    qbx_model = QuickBundlesX(thresholds, metric=metric)
    qbx = qbx_model.cluster(points)
    clusters_0 = qbx.get_clusters(0)
    clusters_1 = qbx.get_clusters(1)
    clusters_2 = qbx.get_clusters(2)
    
    assert_equal(len(clusters_0.centroids), len(clusters_1.centroids))
    assert_equal(len(clusters_2.centroids) > len(clusters_1.centroids), True)
    
    assert_array_equal(clusters_2[1].indices, np.array([3, 4], dtype=np.int32))


def test_with_simulated_bundles():

    streamlines = simulated_bundle(3, False, 2)
    thresholds = [10, 3, 1]
    qbx_class = QuickBundlesX(thresholds)
    qbx = qbx_class.cluster(streamlines)
    for level in range(len(thresholds) + 1):
        clusters = qbx.get_clusters(level)
    tree = qbx.get_tree_cluster_map()
    assert_equal(tree.leaves[0].indices[0], 0)
    assert_equal(tree.leaves[2][0], 2)
    clusters.refdata = streamlines
    
    assert_array_equal(clusters[0][0],
                              np.array([[0., -10.,  -5.],
                                        [0.,  10.,  -5.]]))

    
def test_with_simulated_bundles2():

    # Generate synthetic streamlines
    bundles = bearing_bundles(4, 2)
    bundles.append(straight_bundle(1))
    streamlines = list(itertools.chain(*bundles))

    thresholds = [10, 2, 1]
    qbx_class = QuickBundlesX(thresholds)
    qbx = qbx_class.cluster(streamlines)
    
    tree = qbx.get_tree_cluster_map()
    tree.refdata = streamlines


def show_streamlines(streamlines):
    from dipy.viz import actor, window
    ren = window.Renderer()
    ren.add(actor.line(streamlines))
    window.show(ren)


if __name__ == '__main__':
    run_module_suite()
    