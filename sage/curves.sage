# coding=utf-8
import sys
from sage.schemes.elliptic_curves.ell_curve_isogeny import fill_isogeny_matrix

# Adapted from Warren Moore's scripts.  The main function
# basic_info(curves) takes a list of elliptic curves and outputs a
# data file in the correct format.  Isogenous curves are computed and
# sorted.

# NB requires functionality of Sage-6.3 and code for computing isogeny
# classes as implemented in Sage, but at present (2014-08-14) this has
# not yet all been accepted into Sage (latest version 6.3) but is
# awaiting review at http://trac.sagemath.org/ticket/16743 and the
# dependency http://trac.sagemath.org/ticket/16764.

# List of prime ideals
from sage.schemes.elliptic_curves.isogeny_class import hnf_cmp
def prime_ideals(F, B):
	P = sum([p for p in [F.primes_above(p) for p in primes(B)]], [])
	P.sort(cmp = hnf_cmp)
	return P

# cached field data
Plists = {} # these will all be keyed by fields
Dlists = {} #
Glists = {} #
labels = {} #
cm_j_invariants = {}
used_curves = {}

def add_field(K, charbound=200):
    if K in used_curves:
        return
    Plists[K] = prime_ideals(K, charbound)

    absD = K.discriminant().abs()
    s = K.signature()[0] # number of real places
    d = K.degree()
# Warning: number fields whose label's 4'th component is not 1 will
# not be handled correctly here
    labels[K] = '%s.%s.%s.1' % (str(d),str(s),str(absD))
    Dlists[K] = absD
    Glists[K] = K.galois_group(names='b')
# Get the CM j-invariants
    for d, f, j in cm_j_invariants_and_orders(K):
	cm_j_invariants[j] = d * (f ^ 2)
# Used curves
    used_curves[K] = {}
    ic_cmp[K] = lambda I,J: isog_class_cmp1(K,I,J)

# ap value
def ap(E, p):
	if E.has_good_reduction(p):
		return E.reduction(p).trace_of_frobenius()
	elif E.has_split_multiplicative_reduction(p):
		return 1
	elif E.has_nonsplit_multiplicative_reduction(p):
		return -1
	elif E.has_additive_reduction(p):
		return 0

# Check if we've already found this curve
def found(E, norm = None):
	if norm == None:
		norm = E.conductor().norm()
        K = E.base_field()
	if norm in used_curves[K]:
		for E2 in used_curves[K][norm]:
			if E.is_isomorphic(E2):
				return True
	return False

# Functions for testing if E is a Q-curve


def is_Galois_invariant(N):
        r"""
        Return True if this number field element or ideal is Galois-invariant.
        """
        try:
                K = N.number_field()
        except AttributeError:
                try:
                        K = N.parent()
                except AttributeError:
                        raise ValueError("unable to determine field from %s" % N)
        if K is QQ: return True
        add_field(K)
        G = Glists[K]
        NL = G[0](N) # base-change to Galois closure
        return all([sigma(N)==NL for sigma in G.gens()])

def conj_curve(E,sigma):
        r"""
        Return the Galois conjugate elliptic curve under sigma.
        """
        return EllipticCurve([sigma(a) for a in E.ainvs()])

def is_Q_curve(E):
        r"""
        Return True if this elliptic curve is isogenous to all its
        Galois conjugates.

        Note: if the base field K is not Galois we compute the Galois
        group of its Galois closure L, and test for isogeny over L.
        Is this right?  Following Elkies ('On elliptic K-curves',
        2004) this is the correct set of Galois conjugates but we
        should be looking for isogeny over the algebraic closure.

        If E does not have CM (defined over L) and there is an isogeny
        phi from E to E' where E' is defined over L but phi need not
        be, then considering the composite of phi with the dual of its
        Galois conjugates shows that each of these conjugates is equal
        to phi up to sign.  If the signs are all +1 then phi is also
        defined over L, but otherwise it is only defined over a
        quadratic extension M of L.  In that case, replacing E' by its
        quadratic twist and phi by its composite with the isomorphism
        (defined over M) from E' to its twist gives a new curve
        defined over L and isogenous to E via an L-rational isogeny of
        the same degree as the original phi.  For our test for being a
        Q-curve to be correct (in this non-CM case) -- i.e., agree
        with Elkies' definition -- we require that no quadratic twist
        of a curve L-isogenous to E is a Galois conjugate of E.
        """
        K = E.base_field()
        if K is QQ: return True
        add_field(K)

        # first quick test: are the a-invariants Galois invariant?
        if all([is_Galois_invariant(a) for a in E.ainvs()]):
                return True

        # second quick test: is the conductor invariant?
        if not is_Galois_invariant(E.conductor()):
                return False

        # Retrieve precomputed Galois group and isogeny class and test
        G = Glists[K]
        EL = conj_curve(E,G[0]) # base-change to Galois closure
        C = EL.isogeny_class() # cached
        # Here, 'in' does test up to isomorphism!
        return all([conj_curve(E,sigma) in C for sigma in G.gens()])

def field_data(s):
    r"""
    Returns full field data from field label.
    """
    deg, r1, abs_disc, n = [int(c) for c in s.split(".")]
    sig = [r1, (deg-r1)//2]
    return [s, deg, sig, abs_disc]

def parse_NFelt(K, s):
    r"""
    Returns an element of K defined by the string s.
    """
    return K([QQ(c) for c in s.split(",")])

def ainvs_to_string(ainvs):
        r"""
        Convert a list of n NF elements to a string consisting of n
        substrings separated by spaces, each substring being a
        comma-separated list of strings representing rational numbers
        representing the NF element with respect to its (power) basis.
        """
        return " ".join([",".join([str(c) for c in list(ai)]) for ai in ainvs])

def ainvs_from_strings(K, ainv_string_list):
        r"""
        Reverse of the previous function: converts a list of strings,
        each representing an NF element, to a list of actual NF
        elements in K.
        """
        return [parse_NFelt(K,ai) for ai in ainv_string_list]

def curve_from_strings(K, ainv_string_list):
        r"""
        Given a number field K and a list of 5 strings, each
        representing an NF element, converts these to elements of K
        and returns the elliptic curve with these a-invariants.
        """
        return EllipticCurve(ainvs_from_strings(K,ainv_string_list))

# Isogeny class comparison
ic_cmp = {}
def isog_class_cmp1(k, I, J):
	E_I = curve_from_strings(k,I[0].split()[6:11])
	E_J = curve_from_strings(k,J[0].split()[6:11])

	for p in Plists[k]:
		c = int(ap(E_I, p) - ap(E_J, p))
		if c: return cmp(c,0)

	raise NotImplementedError("Bound on primes is too small to determine...")


fields = {} # keys are field labels, values are NumberFields
def field_from_label(lab):
        if lab in fields:
                return fields[lab]
        dummy, deg, sig, abs_disc = field_data(lab)
        x = polygen(QQ)
        if deg==2:
                d = ZZ(abs_disc)
                if sig[0]==0: d=-d
                t = d%4
                assert t in [0,1]
                pol = x^2 - t*x + (t-d)/4
        elif lab=='3.1.23.1':
                pol = x**3 - x**2 +1
        else:
                raise NotImplementedError("cannot yet handle field %s" % lab)
        K = NumberField(pol, 'a')
        fields[lab] = K
        print "Created field from label %s: %s" % (lab,K)
        return K

def read_curves(infile, only_one=False):
        r"""
        Iterator to loop through lines of a curves.* file each
        containing 13 data fields as defined the in the ecnf-format.txt file,
        yielding its curves as EllipticCurve objects.

        If only_one is True, skips curves whose 4th data field is
        *not* 1, hence only yielding one curve per isogeny class.
        """

        for L in file(infile).readlines():
                #sys.stdout.write(L)
                data = L.split()
                if len(data)!=13:
                        print "line %s does not have 13 fields, skipping" % L
                        continue
                if only_one and data[3]!='1':
                        continue
                K = field_from_label(data[0])
                E = curve_from_strings(K, data[6:11])
                yield E

# Basic info about the curves
def basic_info(curves, outfile = None, verbose=0):
        r"""
        Given a list or iterator yielding a sequence of elliptic
        curves (which could be either an actual list of elliptic
        curves, or something like read_curves(file_name)), processses
        these and writes the results to an output file (if given) and
        to the screen (if verbose>0).

        The input curves do not have to be defined over the same base
        field; the output will be sorted first by field.

        Each curve is first compared with a list of curves previously
        encountered to see if it is isomorphic *or isogenous* to any
        of these, in which case it is ignored.  Hence, if the input
        file contains several curves in an isogeny class, all but the
        first will effectively be ignored.  After that the complete
        isogeny class is computed, sorted, and data for output
        computed for each curve.

        Finally, after all the input and processing are complete, the
        whole lot is output to the file and/or screen, sorted as
        follows: by field, then conductor norm, then conductor (sorted
        using the HNF of the ideal), then by isogeny class (with
        letter labels created on the fly after sorting), then by
        curves in the class.

        TODO:  Also output isogeny matrix information into a separate file.
        """
        if outfile:
                outfile = file(outfile, mode="a")

	data = {}

	for E in curves:
                if verbose>0:
                        print("processing E = %s..." % list(E.ainvs()))
                k = E.base_field()
                add_field(k)
                D = Dlists[k]
                G = Glists[k]
                used = used_curves[k]
                isog_class_cmp = ic_cmp[k]
                field_label = labels[k]
                if not k in data:
                        data[k] = {}
                data_k = data[k]

		# Get a global minimal model for E if possible
                try:
                        E = E.global_minimal_model()
                except:
                        pass
		N = E.conductor()
		norm = N.norm()

		if found(E, norm):
                        if verbose>0:
                                print(" -- isogenous to a previous curve")
                else:
			# Conductor
			hnf = N.pari_hnf()
			cond_label = "[%i,%s,%s]" % (norm, hnf[1][0], hnf[1][1])

			# Setup data
			if norm not in data_k:
				data_k[norm] = {}
			if hnf[1][0] not in data_k[norm]:
				data_k[norm][hnf[1][0]] = {}
			if hnf[1][1] not in data_k[norm][hnf[1][0]]:
				data_k[norm][hnf[1][0]][hnf[1][1]] = []
			else:
                                # This is only useful if we input a
                                # curve which is isogenous to one
                                # already processed but is not
                                # isomorphic to any previously seen,
                                # which only happens if the isog_class
                                # function produced an incomplete list
                                # from the earlier curve!
                                ainvs = E.a_invariants()
				for n, found_isog_class in enumerate(data_k[norm][hnf[1][0]][hnf[1][1]]):
                                        curve_data = found_isog_class[0].split()
					if E.is_isogenous(curve_from_strings(k, curve_data[6:11]), proof = False):
						curve_data[3] = len(found_isog_class)+1
						curve_data[6:11] = [",".join([str(c) for c in ai]) for ai in ainvs]
						data_k[norm][hnf[1][0]][hnf[1][1]][n].append(" ".join(curve_data))
						break

			# Let's find an isogeny class
			isogs, mat = isog_class(E, verbose>1)
			if norm not in used:
				used[norm] = []
			used[norm] += isogs

                        # Q-curve? (isogeny class invariant)
                        q_curve = int(is_Q_curve(E))

			tmp = [] # list of output lines (with
                                 # placeholder for isog code, filled
                                 # in after sorting)

			for n, E2 in enumerate(isogs):
				# a-invs
				ainvs = E2.a_invariants()
                                ainv_string = ainvs_to_string(ainvs)
				# Disc
				j = E2.j_invariant()
				disc = cm_j_invariants.get(j, 0)

				tmp.append("%s %s :isog %i %s %i %s %i %i" % (field_label, cond_label, n + 1, cond_label, norm, ainv_string, disc, q_curve))
                        #print "appending %s curves" % len(tmp)
			data_k[norm][hnf[1][0]][hnf[1][1]].append(tmp)

	# Sort the isogeny classes
        ks = data.keys()
        if verbose>0:
                print
                print "fields: %s" % ks
        ks.sort()
        for k in ks:
            data_k = data[k]
            norms = data_k.keys()
            norms.sort()
            for norm in norms:
                data_k_n = data_k[norm]
		hnf0s = data_k_n.keys()
		hnf0s.sort()
		for hnf0 in hnf0s:
                        data_k_n_h = data_k_n[hnf0]
			hnf1s = data_k_n_h.keys()
			hnf1s.sort()
			for hnf1 in hnf1s:
                                dat = data_k_n_h[hnf1]
				dat.sort(cmp = isog_class_cmp)
				for n, isogs in enumerate(dat):
					isog_letter = chr(97 + n)
					for E_data in isogs:
                                                line = E_data.replace(":isog", isog_letter)
                                                if outfile:
                                                        outfile.write(line+'\n')
						if verbose>0:
                                                        print line
