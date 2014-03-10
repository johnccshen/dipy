import numpy as np
cimport cython
from fused_types cimport floating


cdef inline int _int_max(int a, int b) nogil:
    r"""
    Returns the maximum of a and b
    """
    return a if a >= b else b


cdef inline int _int_min(int a, int b) nogil:
    r"""
    Returns the minimum of a and b
    """
    return a if a <= b else b

cdef enum:
    SI = 0
    SI2 = 1
    SJ = 2
    SJ2 = 3
    SIJ = 4
    CNT = 5

@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
def precompute_cc_factors_3d(floating[:, :, :] static, floating[:, :, :] moving,
                             int radius):
    r"""
    Precomputes the separate terms of the cross correlation metric and image
    norms at each voxel considering a neighborhood of the given radius to 
    efficiently compute the gradient of the metric with respect to the 
    deformation field.

    Parameters
    ----------
    static : array, shape (S, R, C)
        the static volume, which also defines the reference registration domain
    moving : array, shape (S, R, C)
        the moving volume (notice that both images must already be in a common
        reference domain, i.e. the same S, R, C)
    radius : the radius of the neighborhood (a cube of (2*radius+1)^3 voxels)

    Returns
    -------
    factors : array, shape (S, R, C, 5)
        the precomputed cross correlation terms: 
        factors[:,:,:,0] : static minus its mean value along the neighborhood
        factors[:,:,:,1] : sum of squared values of static along the neighborhood
        factors[:,:,:,2] : moving minus its mean value along the neighborhood
        factors[:,:,:,3] : sum of squared values of moving along the neighborhood
        factors[:,:,:,4] : sum of the pointwise products of static and moving
                           along the neighborhood
    """
    cdef int side = 2 * radius + 1
    cdef int ns = static.shape[0]
    cdef int nr = static.shape[1]
    cdef int nc = static.shape[2]
    cdef int s, r, c, k, i, j, t, q, qq, firstc, lastc, firstr, lastr
    cdef double Imean, Jmean
    cdef floating[:, :, :, :] factors = np.zeros((ns, nr, nc, 5), dtype=np.asarray(static).dtype)
    cdef double[:, :] lines = np.zeros((6, side), dtype=np.float64)
    cdef double[:] sums = np.zeros((6,), dtype=np.float64)

    with nogil:
        for r in range(nr):
            firstr = _int_max(0, r - radius)
            lastr = _int_min(nr - 1, r + radius)
            for c in range(nc):
                firstc = _int_max(0, c - radius)
                lastc = _int_min(nc - 1, c + radius)
                # compute factors for line [:,r,c]
                for t in range(6):
                    for q in range(side):
                        lines[t,q] = 0

                # Compute all slices and set the sums on the fly
                # compute each slice [k, i={r-radius..r+radius}, j={c-radius,
                # c+radius}]
                for k in range(ns):
                    q = k % side
                    for t in range(6):
                        sums[t] -= lines[t, q]
                        lines[t, q] = 0
                    for i in range(firstr, lastr + 1):
                        for j in range(firstc, lastc + 1):
                            lines[SI, q] += static[k, i, j]
                            lines[SI2, q] += static[k, i, j] * static[k, i, j]
                            lines[SJ, q] += moving[k, i, j]
                            lines[SJ2, q] += moving[k, i, j] * moving[k, i, j]
                            lines[SIJ, q] += static[k, i, j] * moving[k, i, j]
                            lines[CNT, q] += 1
                    
                    for t in range(6):
                        sums[t] = 0
                        for qq in range(side):
                            sums[t] += lines[t, qq]
                    if(k >= radius):
                        # s is the voxel that is affected by the cube with slices
                        # [s-radius..s+radius, :, :]
                        s = k - radius
                        Imean = sums[SI] / sums[CNT]
                        Jmean = sums[SJ] / sums[CNT]
                        factors[s, r, c, 0] = static[s, r, c] - Imean
                        factors[s, r, c, 1] = moving[s, r, c] - Jmean
                        factors[s, r, c, 2] = sums[SIJ] - Jmean * sums[SI] - \
                            Imean * sums[SJ] + sums[CNT] * Jmean * Imean
                        factors[s, r, c, 3] = sums[SI2] - Imean * sums[SI] - \
                            Imean * sums[SI] + sums[CNT] * Imean * Imean
                        factors[s, r, c, 4] = sums[SJ2] - Jmean * sums[SJ] - \
                            Jmean * sums[SJ] + sums[CNT] * Jmean * Jmean
                # Finally set the values at the end of the line
                for s in range(ns - radius, ns):
                    # this would be the last slice to be processed for voxel
                    # [s,r,c], if it existed
                    k = s + radius
                    q = k % side
                    for t in range(6):
                        sums[t] -= lines[t, q]
                    Imean = sums[SI] / sums[CNT]
                    Jmean = sums[SJ] / sums[CNT]
                    factors[s, r, c, 0] = static[s, r, c] - Imean
                    factors[s, r, c, 1] = moving[s, r, c] - Jmean
                    factors[s, r, c, 2] = sums[SIJ] - Jmean * sums[SI] - \
                        Imean * sums[SJ] + sums[CNT] * Jmean * Imean
                    factors[s, r, c, 3] = sums[SI2] - Imean * sums[SI] - \
                        Imean * sums[SI] + sums[CNT] * Imean * Imean
                    factors[s, r, c, 4] = sums[SJ2] - Jmean * sums[SJ] - \
                        Jmean * sums[SJ] + sums[CNT] * Jmean * Jmean
    return factors


@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
def precompute_cc_factors_3d_test(floating[:, :, :] static, floating[:, :, :] moving,
                                  int radius):
    r"""
    This version of precompute_cc_factors_3d is for testing purposes, it directly
    computes the local cross-correlation without any optimization.
    """
    cdef int ns = static.shape[0]
    cdef int nr = static.shape[1]
    cdef int nc = static.shape[2]
    cdef int s, r, c, k, i, j, t, firstc, lastc, firstr, lastr, firsts, lasts
    cdef double Imean, Jmean
    cdef floating[:, :, :, :] factors = np.zeros((ns, nr, nc, 5), dtype=np.asarray(static).dtype)
    cdef double[:] sums = np.zeros((6,), dtype=np.float64)

    with nogil:
        for s in range(ns):
            firsts = _int_max(0, s - radius)
            lasts = _int_min(ns - 1, s + radius)
            for r in range(nr):
                firstr = _int_max(0, r - radius)
                lastr = _int_min(nr - 1, r + radius)
                for c in range(nc):
                    firstc = _int_max(0, c - radius)
                    lastc = _int_min(nc - 1, c + radius)
                    for t in range(6):
                        sums[t] = 0
                    for k in range(firsts, 1 + lasts):
                        for i in range(firstr, 1 + lastr):
                            for j in range(firstc, 1 + lastc):
                                sums[SI] += static[k, i, j]
                                sums[SI2] += static[k, i,j]**2
                                sums[SJ] += moving[k, i,j]
                                sums[SJ2] += moving[k, i,j]**2
                                sums[SIJ] += static[k,i,j]*moving[k, i,j]
                                sums[CNT] += 1
                    Imean = sums[SI] / sums[CNT]
                    Jmean = sums[SJ] / sums[CNT]
                    factors[s, r, c, 0] = static[s, r, c] - Imean
                    factors[s, r, c, 1] = moving[s, r, c] - Jmean
                    factors[s, r, c, 2] = sums[SIJ] - Jmean * sums[SI] - \
                        Imean * sums[SJ] + sums[CNT] * Jmean * Imean
                    factors[s, r, c, 3] = sums[SI2] - Imean * sums[SI] - \
                        Imean * sums[SI] + sums[CNT] * Imean * Imean
                    factors[s, r, c, 4] = sums[SJ2] - Jmean * sums[SJ] - \
                        Jmean * sums[SJ] + sums[CNT] * Jmean * Jmean  
    return factors


@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
def compute_cc_forward_step_3d(floating[:, :, :, :] grad_static,
                               floating[:, :, :, :] grad_moving,
                               floating[:, :, :, :] factors):
    r"""
    Computes the gradient of the Cross Correlation metric for symmetric
    registration (SyN) w.r.t. the displacement associated to the moving
    volume ('forward' step)

    Parameters
    ----------
    grad_static : array, shape (S, R, C, 3)
        the gradient of the static volume
    grad_moving : array, shape (S, R, C, 3)
        the gradient of the moving volume
    factors : array, shape (S, R, C, 5)
        the precomputed cross correlation terms obtained via 
        precompute_cc_factors_3d

    Returns
    -------
    out : array, shape (S, R, C, 3)
        the gradient of the cross correlation metric with respect to the 
        displacement associated to the moving volume
    energy : the cross correlation energy (data term) at this iteration

    Notes
    -----
    Currently, the gradient of the static image is not being used, but some
    authors suggest that symmetrizing the gradient by including both, the moving
    and static gradients may improve the registration quality. We are leaving 
    this parameters as a placeholder for future investigation
    """
    cdef int ns = grad_static.shape[0]
    cdef int nr = grad_static.shape[1]
    cdef int nc = grad_static.shape[2]
    cdef double energy = 0
    cdef int s,r,c
    cdef double Ii, Ji, sfm, sff, smm, localCorrelation, temp
    cdef floating[:, :, :, :] out = np.zeros((ns, nr, nc, 3), 
                                             dtype=np.asarray(grad_static).dtype)
    with nogil:
        for s in range(ns):
            for r in range(nr):
                for c in range(nc):
                    Ii = factors[s, r, c, 0]
                    Ji = factors[s, r, c, 1]
                    sfm = factors[s, r, c, 2]
                    sff = factors[s, r, c, 3]
                    smm = factors[s, r, c, 4]
                    if(sff == 0.0 or smm == 0.0):
                        continue
                    localCorrelation = 0
                    if(sff * smm > 1e-5):
                        localCorrelation = sfm * sfm / (sff * smm)
                    if(localCorrelation < 1):  # avoid bad values...
                        energy -= localCorrelation
                    temp = 2.0 * sfm / (sff * smm) * (Ii - sfm / smm * Ji)
                    out[s, r, c, 0] += temp * grad_moving[s, r, c, 0]
                    out[s, r, c, 1] += temp * grad_moving[s, r, c, 1]
                    out[s, r, c, 2] += temp * grad_moving[s, r, c, 2]
    return out, energy

@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)

def compute_cc_backward_step_3d(floating[:, :, :, :] grad_static,
                                floating[:, :, :, :] grad_moving,
                                floating[:, :, :, :] factors):
    r"""
    Computes the gradient of the Cross Correlation metric for symmetric
    registration (SyN) w.r.t. the displacement associated to the static
    volume ('backward' step)

    Parameters
    ----------
    grad_static : array, shape (S, R, C, 3)
        the gradient of the static volume
    grad_moving : array, shape (S, R, C, 3)
        the gradient of the moving volume
    factors : array, shape (S, R, C, 5)
        the precomputed cross correlation terms obtained via 
        precompute_cc_factors_3d

    Returns
    -------
    out : array, shape (S, R, C, 3)
        the gradient of the cross correlation metric with respect to the 
        displacement associated to the static volume
    energy : the cross correlation energy (data term) at this iteration

    Notes
    -----
    Currently, the gradient of the moving image is not being used, but some
    authors suggest that symmetrizing the gradient by including both, the moving
    and static gradients may improve the registration quality. We are leaving 
    this parameters as a placeholder for future investigation
    """
    cdef int ns = grad_static.shape[0]
    cdef int nr = grad_static.shape[1]
    cdef int nc = grad_static.shape[2]
    cdef int s,r,c
    cdef double energy = 0
    cdef double Ii, Ji, sfm, sff, smm, localCorrelation, temp
    cdef floating[:, :, :, :] out = np.zeros((ns, nr, nc, 3), 
                                             dtype=np.asarray(grad_static).dtype)

    with nogil:

        for s in range(ns):
            for r in range(nr):
                for c in range(nc):
                    Ii = factors[s, r, c, 0]
                    Ji = factors[s, r, c, 1]
                    sfm = factors[s, r, c, 2]
                    sff = factors[s, r, c, 3]
                    smm = factors[s, r, c, 4]
                    if(sff == 0.0 or smm == 0.0):
                        continue
                    localCorrelation = 0
                    if(sff * smm > 1e-5):
                        localCorrelation = sfm * sfm / (sff * smm)
                    if(localCorrelation < 1):  # avoid bad values...
                        energy -= localCorrelation
                    temp = 2.0 * sfm / (sff * smm) * (Ji - sfm / sff * Ii)
                    out[s, r, c, 0] += temp * grad_static[s, r, c, 0]
                    out[s, r, c, 1] += temp * grad_static[s, r, c, 1]
                    out[s, r, c, 2] += temp * grad_static[s, r, c, 2]
    return out, energy




@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
def precompute_cc_factors_2d(floating[:, :] static, floating[:, :] moving,
                             int radius):
    r"""
    Precomputes the separate terms of the cross correlation metric and image
    norms at each voxel considering a neighborhood of the given radius to 
    efficiently compute the gradient of the metric with respect to the 
    deformation field.

    Parameters
    ----------
    static : array, shape (R, C)
        the static volume, which also defines the reference registration domain
    moving : array, shape (R, C)
        the moving volume (notice that both images must already be in a common
        reference domain, i.e. the same R, C)
    radius : the radius of the neighborhood (a square of (2*radius+1)^2 voxels)

    Returns
    -------
    factors : array, shape (R, C, 5)
        the precomputed cross correlation terms: 
        factors[:,:,0] : static minus its mean value along the neighborhood
        factors[:,:,1] : sum of squared values of static along the neighborhood
        factors[:,:,2] : moving minus its mean value along the neighborhood
        factors[:,:,3] : sum of squared values of moving along the neighborhood
        factors[:,:,4] : sum of the pointwise products of static and moving
                           along the neighborhood
    """
    cdef int side = 2 * radius + 1
    cdef int nr = static.shape[0]
    cdef int nc = static.shape[1]
    cdef int r, c, i, j, t, q, qq, firstc, lastc
    cdef double Imean, Jmean
    cdef floating[:, :, :] factors = np.zeros((nr, nc, 5), dtype=np.asarray(static).dtype)
    cdef double[:, :] lines = np.zeros((6, side), dtype=np.float64)
    cdef double[:] sums = np.zeros((6,), dtype=np.float64)

    with nogil:

        for c in range(nc):
            firstc = _int_max(0, c - radius)
            lastc = _int_min(nc - 1, c + radius)
            # compute factors for row [:,c]
            for t in range(6):
                for q in range(side):
                    lines[t,q] = 0
            # Compute all rows and set the sums on the fly
            # compute row [i, j={c-radius, c+radius}]
            for i in range(nr):
                q = i % side
                for t in range(6):
                    lines[t, q] = 0
                for j in range(firstc, lastc + 1):
                    lines[SI, q] += static[i, j]
                    lines[SI2, q] += static[i, j] * static[i, j]
                    lines[SJ, q] += moving[i, j]
                    lines[SJ2, q] += moving[i, j] * moving[i, j]
                    lines[SIJ, q] += static[i, j] * moving[i, j]
                    lines[CNT, q] += 1
                
                for t in range(6):
                    sums[t] = 0
                    for qq in range(side):
                        sums[t] += lines[t, qq]
                if(i >= radius):
                    # r is the pixel that is affected by the cube with slices
                    # [r-radius..r+radius, :]
                    r = i - radius
                    Imean = sums[SI] / sums[CNT]
                    Jmean = sums[SJ] / sums[CNT]
                    factors[r, c, 0] = static[r, c] - Imean
                    factors[r, c, 1] = moving[r, c] - Jmean
                    factors[r, c, 2] = sums[SIJ] - Jmean * sums[SI] - \
                        Imean * sums[SJ] + sums[CNT] * Jmean * Imean
                    factors[r, c, 3] = sums[SI2] - Imean * sums[SI] - \
                        Imean * sums[SI] + sums[CNT] * Imean * Imean
                    factors[r, c, 4] = sums[SJ2] - Jmean * sums[SJ] - \
                        Jmean * sums[SJ] + sums[CNT] * Jmean * Jmean
            # Finally set the values at the end of the line
            for r in range(nr - radius, nr):
                # this would be the last slice to be processed for pixel
                # [r,c], if it existed
                i = r + radius
                q = i % side
                for t in range(6):
                    sums[t] -= lines[t, q]
                Imean = sums[SI] / sums[CNT]
                Jmean = sums[SJ] / sums[CNT]
                factors[r, c, 0] = static[r, c] - Imean
                factors[r, c, 1] = moving[r, c] - Jmean
                factors[r, c, 2] = sums[SIJ] - Jmean * sums[SI] - \
                    Imean * sums[SJ] + sums[CNT] * Jmean * Imean
                factors[r, c, 3] = sums[SI2] - Imean * sums[SI] - \
                    Imean * sums[SI] + sums[CNT] * Imean * Imean
                factors[r, c, 4] = sums[SJ2] - Jmean * sums[SJ] - \
                    Jmean * sums[SJ] + sums[CNT] * Jmean * Jmean
    return factors


@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
def precompute_cc_factors_2d_test(floating[:, :] static, floating[:, :] moving,
                                  int radius):
    r"""
    This version of precompute_cc_factors_2d is for testing purposes, it directly
    computes the local cross-correlation without any optimization.
    
    """
    cdef int nr = static.shape[0]
    cdef int nc = static.shape[1]
    cdef int r, c, i, j, t, firstr, lastr, firstc, lastc
    cdef double Imean, Jmean
    cdef floating[:, :, :] factors = np.zeros((nr, nc, 5), dtype=np.asarray(static).dtype)
    cdef double[:] sums = np.zeros((6,), dtype=np.float64)

    with nogil:

        for r in range(nr):
            firstr = _int_max(0, r - radius)
            lastr = _int_min(nr - 1, r + radius)
            for c in range(nc):
                firstc = _int_max(0, c - radius)
                lastc = _int_min(nc - 1, c + radius)
                for t in range(6):
                    sums[t]=0
                for i in range(firstr, 1 + lastr):
                    for j in range(firstc, 1+lastc):
                        sums[SI] += static[i, j]
                        sums[SI2] += static[i,j]**2
                        sums[SJ] += moving[i,j]
                        sums[SJ2] += moving[i,j]**2
                        sums[SIJ] += static[i,j]*moving[i,j]
                        sums[CNT] += 1
                Imean = sums[SI] / sums[CNT]
                Jmean = sums[SJ] / sums[CNT]
                factors[r, c, 0] = static[r, c] - Imean
                factors[r, c, 1] = moving[r, c] - Jmean
                factors[r, c, 2] = sums[SIJ] - Jmean * sums[SI] - \
                    Imean * sums[SJ] + sums[CNT] * Jmean * Imean
                factors[r, c, 3] = sums[SI2] - Imean * sums[SI] - \
                    Imean * sums[SI] + sums[CNT] * Imean * Imean
                factors[r, c, 4] = sums[SJ2] - Jmean * sums[SJ] - \
                        Jmean * sums[SJ] + sums[CNT] * Jmean * Jmean
    return factors


@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)

def compute_cc_forward_step_2d(floating[:, :, :] grad_static,
                               floating[:, :, :] grad_moving,
                               floating[:, :, :] factors):
    r"""
    Computes the gradient of the Cross Correlation metric for symmetric
    registration (SyN) w.r.t. the displacement associated to the moving
    image ('backward' step)

    Parameters
    ----------
    grad_static : array, shape (R, C, 2)
        the gradient of the static image
    grad_moving : array, shape (R, C, 2)
        the gradient of the moving image
    factors : array, shape (R, C, 5)
        the precomputed cross correlation terms obtained via 
        precompute_cc_factors_2d

    Returns
    -------
    out : array, shape (R, C, 2)
        the gradient of the cross correlation metric with respect to the 
        displacement associated to the moving image
    energy : the cross correlation energy (data term) at this iteration

    Notes
    -----
    Currently, the gradient of the static image is not being used, but some
    authors suggest that symmetrizing the gradient by including both, the moving
    and static gradients may improve the registration quality. We are leaving 
    this parameters as a placeholder for future investigation
    """
    cdef int nr = grad_static.shape[0]
    cdef int nc = grad_static.shape[1]
    cdef double energy = 0
    cdef int r,c
    cdef double Ii, Ji, sfm, sff, smm, localCorrelation, temp
    cdef floating[:, :, :] out = np.zeros((nr, nc, 2), 
                                    dtype=np.asarray(grad_static).dtype)
    with nogil:
            
        for r in range(nr):
            for c in range(nc):
                Ii = factors[r, c, 0]
                Ji = factors[r, c, 1]
                sfm = factors[r, c, 2]
                sff = factors[r, c, 3]
                smm = factors[r, c, 4]
                if(sff == 0.0 or smm == 0.0):
                    continue
                localCorrelation = 0
                if(sff * smm > 1e-5):
                    localCorrelation = sfm * sfm / (sff * smm)
                if(localCorrelation < 1):  # avoid bad values...
                    energy -= localCorrelation
                temp = 2.0 * sfm / (sff * smm) * (Ii - sfm / smm * Ji)
                out[r, c, 0] += temp * grad_moving[r, c, 0]
                out[r, c, 1] += temp * grad_moving[r, c, 1]
    return out, energy


@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
def compute_cc_backward_step_2d(floating[:, :, :] grad_static,
                                floating[:, :, :] grad_moving,
                                floating[:, :, :] factors):
    r"""
    Computes the gradient of the Cross Correlation metric for symmetric
    registration (SyN) w.r.t. the displacement associated to the static
    image ('forward' step)

    Parameters
    ----------
    grad_static : array, shape (R, C, 2)
        the gradient of the static image
    grad_moving : array, shape (R, C, 2)
        the gradient of the moving image
    factors : array, shape (R, C, 5)
        the precomputed cross correlation terms obtained via 
        precompute_cc_factors_2d

    Returns
    -------
    out : array, shape (R, C, 2)
        the gradient of the cross correlation metric with respect to the 
        displacement associated to the static image
    energy : the cross correlation energy (data term) at this iteration

    Notes
    -----
    Currently, the gradient of the moving image is not being used, but some
    authors suggest that symmetrizing the gradient by including both, the moving
    and static gradients may improve the registration quality. We are leaving 
    this parameters as a placeholder for future investigation
    """
    cdef int nr = grad_static.shape[0]
    cdef int nc = grad_static.shape[1]
    cdef int r,c
    cdef double energy = 0
    cdef double Ii, Ji, sfm, sff, smm, localCorrelation, temp
    cdef floating[:, :, :] out = np.zeros((nr, nc, 3), 
                                             dtype=np.asarray(grad_static).dtype)

    with nogil:

        for r in range(nr):
            for c in range(nc):
                Ii = factors[r, c, 0]
                Ji = factors[r, c, 1]
                sfm = factors[r, c, 2]
                sff = factors[r, c, 3]
                smm = factors[r, c, 4]
                if(sff == 0.0 or smm == 0.0):
                    continue
                localCorrelation = 0
                if(sff * smm > 1e-5):
                    localCorrelation = sfm * sfm / (sff * smm)
                if(localCorrelation < 1):  # avoid bad values...
                    energy -= localCorrelation
                temp = 2.0 * sfm / (sff * smm) * (Ji - sfm / sff * Ii)
                out[r, c, 0] += temp * grad_static[r, c, 0]
                out[r, c, 1] += temp * grad_static[r, c, 1]
    return out, energy
