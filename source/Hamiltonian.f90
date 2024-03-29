!> \brief contains the subprograms needed to build the hamiltonian and some forces
!> \author Alin M Elena
!> \date 07/11/07, 10:09:17
!
module m_Hamiltonian
  use m_Constants
  use m_Types
  use m_Useful
  use m_LinearAlgebra
  use m_SlaterKoster
  use m_Gutenberg, only: PrintMatrix
  use m_TightBinding
  use m_DensityMatrix
  private
!
  public :: BuildHamiltonian
  public :: AddBias
  public :: DiagHamiltonian
  public :: ZeroForces
  public :: RepulsiveForces
  public :: ElectronicForces
  public :: ElectronicEnergy
  public :: RepulsiveEnergy
contains
!
!> \brief builds the hamiltonian
!> \author Cristian G Sanchez, Alin M Elena
!> \date 07/11/07, 10:09:17
!> \param io type(ioType) contains all the info about I/O files
!> \param gen type(generalType) contains the info needed by the program to k_run
!> \param atomic type(atomicxType) contains all info about the atoms and basis set and some parameters
!> \param tbMod type(modelType) contains information about the tight binding model parameters
!> \param sol type(solutionType) contains information about the solution space
!
!
  subroutine BuildHamiltonian (io, gen, atomic, tbMod, sol)
    character (len=*), parameter :: myname = "BuildHamiltonian"
    type (ioType), intent (inout) :: io
    type (generalType), intent (inout) :: gen
    type (atomicxType), intent (inout) :: atomic
    type (modelType), intent (inout) :: tbMod
    type (solutionType), intent (inout) :: sol
    integer :: i, j, k, o, norbsi, norbsj
    real (kind=k_pr) :: rij, hij, l, m, n
!-------------------------------------------------!
!
    call ZeroMatrix (sol%h, io)
    if ( .not. gen%spin) then
!!!!!   !$OMP PARALLEL DO DEFAULT(shared) PRIVATE(i,j,k,o,hij,rij,l,m,n)  SCHEDULE(static)
      do i = 1, atomic%atoms%natoms - 1
        do j = i + 1, atomic%atoms%natoms
! Offsite terms
          call AtomDistance (atomic%atoms, j, i, rij, l, m, n)
          do k = 1, atomic%species%norbs(atomic%atoms%sp(i))
            do o = 1, atomic%species%norbs(atomic%atoms%sp(j))
              hij = hmn (rij, l, m, n, atomic%basis%orbitals(atomic%atoms%orbs(i, k)), atomic%basis%orbitals(atomic%atoms%orbs(j, &
             & o)), gen, tbMod, sol)
              if (Abs(hij) >= gen%hElementThreshold) then
                call SpmPut (sol%h, atomic%atoms%orbs(i, k), atomic%atoms%orbs(j, o), cmplx(hij, 0.0_k_pr, k_pr))
                call SpmPut (sol%h, atomic%atoms%orbs(j, o), atomic%atoms%orbs(i, k), cmplx(hij, 0.0_k_pr, k_pr))
              end if
            end do
          end do
        end do
!            Onsite terms
        do k = 1, atomic%species%norbs(atomic%atoms%sp(i))
          do o = 1, atomic%species%norbs(atomic%atoms%sp(i))
            hij = Onsite (atomic%basis%orbitals(atomic%atoms%orbs(i, k)), atomic%basis%orbitals(atomic%atoms%orbs(i, o)), tbMod)
            call SpmPut (sol%h, atomic%atoms%orbs(i, k), atomic%atoms%orbs(i, o), cmplx(hij, 0.0_k_pr, k_pr))
          end do
        end do
      end do
! this may look silly but the standard does not specify the value of i at the end of the loop
      i = atomic%atoms%natoms
      do k = 1, atomic%species%norbs(atomic%atoms%sp(i))
        do o = 1, atomic%species%norbs(atomic%atoms%sp(i))
          hij = Onsite (atomic%basis%orbitals(atomic%atoms%orbs(i, k)), atomic%basis%orbitals(atomic%atoms%orbs(i, o)), tbMod)
          call SpmPut (sol%h, atomic%atoms%orbs(i, k), atomic%atoms%orbs(i, o), cmplx(hij, 0.0_k_pr, k_pr))
        end do
      end do
!!!!!   !$OMP END PARALLEL DO
    else if (gen%collinear) then
      do i = 1, atomic%atoms%natoms - 1
        norbsi = atomic%species%norbs(atomic%atoms%sp(i)) / 2
        do j = i + 1, atomic%atoms%natoms
          norbsj = atomic%species%norbs(atomic%atoms%sp(j)) / 2
! Offsite terms
          call AtomDistance (atomic%atoms, j, i, rij, l, m, n)
          do k = 1, norbsi
            do o = 1, norbsj
              hij = hmn (rij, l, m, n, atomic%basis%orbitals(atomic%atoms%orbs(i, k)), atomic%basis%orbitals(atomic%atoms%orbs(j, &
             & o)), gen, tbMod, sol)
              if (Abs(hij) >= gen%hElementThreshold) then
                call SpmPut (sol%h, atomic%atoms%orbs(i, k), atomic%atoms%orbs(j, o), cmplx(hij, 0.0_k_pr, k_pr))
                call SpmPut (sol%h, atomic%atoms%orbs(j, o), atomic%atoms%orbs(i, k), cmplx(hij, 0.0_k_pr, k_pr))
              end if
              hij = hmn (rij, l, m, n, atomic%basis%orbitals(atomic%atoms%orbs(i, k+norbsi)), &
             & atomic%basis%orbitals(atomic%atoms%orbs(j, o+norbsj)), gen, tbMod, sol)
              if (Abs(hij) >= gen%hElementThreshold) then
                call SpmPut (sol%h, atomic%atoms%orbs(i, k+norbsi), atomic%atoms%orbs(j, o+norbsj), cmplx(hij, 0.0_k_pr, k_pr))
                call SpmPut (sol%h, atomic%atoms%orbs(j, o+norbsj), atomic%atoms%orbs(i, k+norbsi), cmplx(hij, 0.0_k_pr, k_pr))
              end if
            end do
          end do
        end do
!            Onsite terms
        do k = 1, norbsi
          do o = 1, norbsi
            hij = Onsite (atomic%basis%orbitals(atomic%atoms%orbs(i, k)), atomic%basis%orbitals(atomic%atoms%orbs(i, o)), tbMod)
            call SpmPut (sol%h, atomic%atoms%orbs(i, k), atomic%atoms%orbs(i, o), cmplx(hij, 0.0_k_pr, k_pr))
            hij = Onsite (atomic%basis%orbitals(atomic%atoms%orbs(i, k+norbsi)), atomic%basis%orbitals(atomic%atoms%orbs(i, &
           & o+norbsi)), tbMod)
            call SpmPut (sol%h, atomic%atoms%orbs(i, k+norbsi), atomic%atoms%orbs(i, o+norbsi), cmplx(hij, 0.0_k_pr, k_pr))
          end do
        end do
      end do
      i = atomic%atoms%natoms
      norbsi = atomic%species%norbs(atomic%atoms%sp(i)) / 2
      do k = 1, norbsi
        do o = 1, norbsi
          hij = Onsite (atomic%basis%orbitals(atomic%atoms%orbs(i, k)), atomic%basis%orbitals(atomic%atoms%orbs(i, o)), tbMod)
          call SpmPut (sol%h, atomic%atoms%orbs(i, k), atomic%atoms%orbs(i, o), cmplx(hij, 0.0_k_pr, k_pr))
          hij = Onsite (atomic%basis%orbitals(atomic%atoms%orbs(i, k+norbsi)), atomic%basis%orbitals(atomic%atoms%orbs(i, &
         & o+norbsi)), tbMod)
          call SpmPut (sol%h, atomic%atoms%orbs(i, k+norbsi), atomic%atoms%orbs(i, o+norbsi), cmplx(hij, 0.0_k_pr, k_pr))
        end do
      end do
!
!
    else
      call error ("Non-Collinear spins are not implemented yet!", myname, .true., io)
    end if
  end subroutine BuildHamiltonian
!
!
!
!> \brief adds an external field to the diagonal elements of the Hamiltonian                                 !
!> \author Cristian G. Sanchez
!> \date ~2005
!> \param atomic type(atomicType) contains all info about the atoms and basis set and some parameters
!> \param sol type(solutionType) contains information about the solution space
!> \param factor real multiplies the bias
!
  subroutine AddBias (factor, atomic, sol)
    character (len=*), parameter :: myname = 'AddBias'
    real (k_pr), intent (in) :: factor
    type (atomicxType), intent (in) :: atomic
    type (solutionType), intent (inout) :: sol
    integer :: i, k
!
    do i = 1, atomic%atoms%natoms
      do k = 1, atomic%species%norbs(atomic%atoms%sp(i))
        sol%h%a (atomic%atoms%orbs(i, k), atomic%atoms%orbs(i, k)) = sol%h%a(atomic%atoms%orbs(i, k), atomic%atoms%orbs(i, k)) + &
       & cmplx (factor*atomic%atoms%bias(i), 0.0_k_pr, k_pr)
      end do
    end do
!
  end subroutine AddBias
!
!> \brief diagonalizes the hamiltonian
!> \author Cristian G. Sanchez, Alin M Elena
!> \date 07/11/07, 13:04:42
!> \param io type(ioType) contains all the info about I/O files
!> \param gen type(generalType) contains the info needed by the program to k_run
!> \param sol type(solutionType) contains information about the solution space
!> \param atomic type(atomicxType) contains all info about the atoms and basis set and some parameters
!
  subroutine DiagHamiltonian (io, gen, atomic, sol)
    character (len=*), parameter :: myname = 'DiagHamiltonian'
    type (ioType), intent (inout) :: io
    type (generalType), intent (inout) :: gen
    type (solutionType), intent (inout) :: sol
    type (atomicxType), intent (inout) :: atomic
    integer :: n, ns, i, j
    if (gen%spin) then
      n = sol%h%dim
      ns = sol%hup%dim
      sol%eigenvals (1:n) = 0.0_k_pr
      call ZeroMatrix (sol%eigenvecs, io)
      do i = 1, ns
        do j = 1, ns
          sol%hdown%a (i, j) = sol%h%a(i, j)
          sol%buff%h%a(i, j) = sol%h%a(i, j)
        end do
      end do
      sol%buff%tmpA = 0.0_k_pr
      call ZeroMatrix (sol%buff%tmpB, io)
      call DiagonalizeMatrix (sol%buff%h, sol%buff%tmpB, sol%buff%tmpA, io)
      sol%eigenvals (1:ns) = sol%buff%tmpA(1:ns)
      do i = 1, ns
        do j = 1, ns
          sol%eigenvecs%a (i, j) = sol%buff%tmpB%a(i, j)
          sol%hup%a (i, j) = sol%h%a(i+ns, j+ns)
          sol%buff%h%a(i, j) = sol%h%a(i+ns, j+ns)
        end do
      end do
      sol%buff%tmpA = 0.0_k_pr
      call ZeroMatrix (sol%buff%tmpB, io)
      call DiagonalizeMatrix (sol%buff%h, sol%buff%tmpB, sol%buff%tmpA, io)
      sol%eigenvals (1+ns:n) = sol%buff%tmpA(1:ns)
      do i = 1, ns
        do j = 1, ns
          sol%eigenvecs%a (i+ns, j+ns) = sol%buff%tmpB%a(i, j)
        end do
      end do
!
      if (gen%lIsExcited) then
        call CreateDensityMatrixExcited (gen, atomic, sol, io)
      else
        call CreateDensityMatrixSpin (gen, atomic, sol, io)
      end if

    else
      sol%eigenvals = 0.0_k_pr
      call ZeroMatrix (sol%eigenvecs, io)
      call CopyMatrix (sol%buff%h, sol%h, io)
      call DiagonalizeMatrix (sol%h, sol%eigenvecs, sol%eigenvals, io)
      call CreateDensityMatrixNoSpin (gen, atomic, sol, io)
    end if
!
  end subroutine DiagHamiltonian
!
!> \brief resets the forces
!> \author Alin M Elena
!> \date 07/11/07, 16:43:12
!> \param atomic type(atomicxType) info about the atoms
!
  subroutine ZeroForces (atomic)
    character (len=*), parameter :: sMyName = "ZeroForces"
    type (atomicxType), intent (inout) :: atomic
!
    atomic%atoms%fx = 0.0_k_pr
    atomic%atoms%fy = 0.0_k_pr
    atomic%atoms%fz = 0.0_k_pr
!
  end subroutine ZeroForces
!
!> \brief computes the contribution to forces by the repulsive potential
!> \author Alin M Elena
!> \date 07/11/07, 17:20:31
!> \param atomic type(atomicType) info about the atoms
!> \param gen type(generalType) contains the info needed by the program to k_run
!> \param tb type(modelType) contains information about the tight binding model parameters
  subroutine RepulsiveForces (gen, atomic, tb)
!--subroutine name--------------------------------!
    character (len=*), parameter :: myname = 'RepulsiveForces'
    type (atomicType), intent (inout) :: atomic
    type (generalType), intent (inout) :: gen
    type (modelType), intent (inout) :: tb
    real (k_pr) :: rij, rbr, rib !, rir
    real (k_pr) :: rxij, ryij, rzij
    real (k_pr) :: rxbr, rybr, rzbr
    real (k_pr) :: rxib, ryib, rzib
!    real(k_pr) :: rxir, ryir, rzir
    integer :: i, j, b, r, k
    real (k_pr) :: fact, fact1
!-------------------------------------------------!
!
    if ( .not. gen%embedding) then
!
      do k = 1, atomic%nmoving
        i = atomic%moving (k)
        do j = 1, atomic%natoms
          if (i /= j) then
            call AtomDistVec (atomic, i, j, rij, rxij, ryij, rzij)
            fact = - RepP (rij, atomic%sp(i), atomic%sp(j), tb, gen) / rij
            atomic%fx (i) = atomic%fx(i) + fact * rxij
            atomic%fy (i) = atomic%fy(i) + fact * ryij
            atomic%fz (i) = atomic%fz(i) + fact * rzij
          end if
        end do
      end do
    else ! now with embedding
      do k = 1, atomic%nmoving
        b = atomic%moving (k)
        do i = 1, atomic%natoms
          if (i /= b) then
            call AtomDistVec (atomic, i, b, rib, rxib, ryib, rzib)
            fact = - RepP (rib, atomic%sp(i), atomic%sp(b), tb, gen) * EmbeddingP (argument(i), atomic%sp(b), tb) / rib
            atomic%fx (b) = atomic%fx(b) - fact * rxib
            atomic%fy (b) = atomic%fy(b) - fact * ryib
            atomic%fz (b) = atomic%fz(b) - fact * rzib
          end if
        end do
        fact1 = EmbeddingP (argument(b), atomic%sp(b), tb)
        do r = 1, atomic%natoms
          if (b /= r) then
            call AtomDistVec (atomic, b, r, rbr, rxbr, rybr, rzbr)
            fact = - fact1 * RepP (rbr, atomic%sp(b), atomic%sp(r), tb, gen) / rbr
            atomic%fx (b) = atomic%fx(b) + fact * rxbr
            atomic%fy (b) = atomic%fy(b) + fact * rybr
            atomic%fz (b) = atomic%fz(b) + fact * rzbr
          end if
        end do
      end do
    end if
!
  contains
    function argument (m)
      integer :: m
      real (k_pr) :: argument
      integer :: i
      real (k_pr) :: sum, rim
!
      sum = 0.0_k_pr
      do i = 1, atomic%natoms
        if (i /= m) then
          rim = Distance (atomic, i, m)
          sum = sum + Rep (rim, atomic%sp(i), atomic%sp(m), tb, gen)
        end if
      end do
      argument = sum
    end function argument
  end subroutine RepulsiveForces
!
!> \brief calculates force operator
!> \author Cristian G Sanchez
!> \date ~2005
!> \param alpha integer the direction 1-2-3 ->x-y-z
!> \param j integer the atom
!> \param gen type(generalType) contains the info needed by the program to k_run
!> \param atomic type(atomicType) contains all info about the atoms and basis set and some parameters
!> \param tb type(modelType) contains information about the tight binding model parameters
!> \param sol type(solutionType) contains information about the solution space
!> \param io type(ioType) contains all the info about I/O files
  subroutine ForceOperator (j, atomic, gen, tb, sol, io)
!--subroutine name--------------------------------!
    character (len=*), parameter :: myname = 'ForceOperator'
!--subroutine parameters -------------------------!
    integer, intent (inout) :: j
    type (generalType), intent (inout) :: gen
    type (atomicxType), intent (inout) :: atomic
    type (modelType), intent (inout) :: tb
    type (solutionType), intent (inout) :: sol
    type (ioType), intent (inout) :: io
!--internal variables ----------------------------!
    real (k_pr) :: rij
    integer :: i, k, o
    real (k_pr) :: fact (3), l, m, n !,fact2,ff2,
!-------------------------------------------------!
!
    call ZeroMatrix (sol%forceOpX, io)
    call ZeroMatrix (sol%forceOpY, io)
    call ZeroMatrix (sol%forceOpZ, io)
    do i = 1, atomic%atoms%natoms
      if (i /= j) then
        call AtomDistance (atomic%atoms, j, i, rij, l, m, n)
        do k = 1, atomic%species%norbs(atomic%atoms%sp(i))
          do o = 1, atomic%species%norbs(atomic%atoms%sp(j))
            fact = - DhmnXYZ (rij, l, m, n, atomic%basis%orbitals(atomic%atoms%orbs(i, k)), &
           & atomic%basis%orbitals(atomic%atoms%orbs(j, o)), gen, tb, sol)
            call SpmPut (sol%forceOpX, atomic%atoms%orbs(i, k), atomic%atoms%orbs(j, o), cmplx(fact(1), 0.0_k_pr, k_pr))
            call SpmPut (sol%forceOpX, atomic%atoms%orbs(j, o), atomic%atoms%orbs(i, k), cmplx(fact(1), 0.0_k_pr, k_pr))
            call SpmPut (sol%forceOpY, atomic%atoms%orbs(i, k), atomic%atoms%orbs(j, o), cmplx(fact(2), 0.0_k_pr, k_pr))
            call SpmPut (sol%forceOpY, atomic%atoms%orbs(j, o), atomic%atoms%orbs(i, k), cmplx(fact(2), 0.0_k_pr, k_pr))
            call SpmPut (sol%forceOpZ, atomic%atoms%orbs(i, k), atomic%atoms%orbs(j, o), cmplx(fact(3), 0.0_k_pr, k_pr))
            call SpmPut (sol%forceOpZ, atomic%atoms%orbs(j, o), atomic%atoms%orbs(i, k), cmplx(fact(3), 0.0_k_pr, k_pr))
          end do
        end do
      end if
    end do
  end subroutine ForceOperator
!
!> \brief adds electronic contribution to forces
!> \author Alin M Elena
!> \date 07/11/07, 18:30:30
!> \param io type(ioType) contains all the info about I/O files
!> \param gen type(generalType) contains the info needed by the program to k_run
!> \param atomic type(atomicxType) contains all info about the atoms and basis set and some parameters
!> \param tb type(modelType) contains information about the tight binding model parameters
!> \param sol type(solutionType) contains information about the solution space
  subroutine ElectronicForces (atomic, gen, tb, sol, io)
    character (len=*), parameter :: myname = 'ElectronicForces'
    type (generalType), intent (inout) :: gen
    type (atomicxType), intent (inout) :: atomic
    type (modelType), intent (inout) :: tb
    type (solutionType), intent (inout) :: sol
    type (ioType), intent (inout) :: io
    integer :: i, k
!
!
    do k = 1, atomic%atoms%nmoving
      i = atomic%atoms%moving(k)
      call ForceOperator (i, atomic, gen, tb, sol, io)
      atomic%atoms%fx (i) = atomic%atoms%fx(i) + ProductTrace (sol%rho, sol%forceOpX, io)
      atomic%atoms%fy (i) = atomic%atoms%fy(i) + ProductTrace (sol%rho, sol%forceOpY, io)
      atomic%atoms%fz (i) = atomic%atoms%fz(i) + ProductTrace (sol%rho, sol%forceOpZ, io)
    end do
!
  end subroutine ElectronicForces
!
!> \brief computes the electronic energy
!> \author Alin M Elena
!> \date 07/11/07, 23:15:07
!> \param io type(ioType) contains all the info about I/O files
!> \param gen type(generalType) contains the info needed by the program to k_run
!> \param sol type(solutionType) contains information about the solution space
!> \remarks \f[ E_e=Tr(\rho {\mathbf H})\f]
  real (k_pr) function ElectronicEnergy (gen, sol, io)
    character (len=*), parameter :: myname = 'ElectronicEnergy'
    type (solutionType), intent (inout) :: sol
    type (ioType), intent (inout) :: io
    type (generalType), intent (in) :: gen
!-------------------------------------------------!
!
!
    ElectronicEnergy = ProductTrace (sol%rho, sol%h, io)
!
  end function ElectronicEnergy
!
!> \brief computes repulsive energy
!> \author Alin M Elena
!> \date 07/11/07, 23:25:42
!> \param gen type(generalType) contains the info needed by the program to k_run
!> \param atomic type(atomicType) contains all info about the atoms and basis set and some parameters
!> \param tb type(modelType) contains information about the tight binding model parameters
  real (k_pr) function RepulsiveEnergy (gen, atomic, tb)
!--subroutine name--------------------------------!
    character (len=*), parameter :: myname = 'RepulsiveEnergy'
    real (k_pr) :: renergy, phi
    real (k_pr) :: rij
    type (modelType), intent (inout) :: tb
    type (generalType), intent (inout) :: gen
    type (atomicType), intent (inout) :: atomic
    integer :: i, j
!
    renergy = 0.0_k_pr
    if ( .not. gen%embedding) then
      do i = 1, atomic%natoms - 1
        do j = i + 1, atomic%natoms
          rij = Distance (atomic, i, j)
          renergy = renergy + Rep (rij, atomic%sp(i), atomic%sp(j), tb, gen)
        end do
      end do
    else
      do i = 1, atomic%natoms
        phi = 0.0_k_pr
        do j = 1, atomic%natoms
          if (i /= j) then
            rij = Distance (atomic, i, j)
            phi = phi + Rep (rij, atomic%sp(i), atomic%sp(j), tb, gen)
          end if
        end do
        renergy = renergy + embedding (phi, atomic%sp(i), tb)
      end do
    end if
    RepulsiveEnergy = renergy
!
  end function RepulsiveEnergy
!
end module m_Hamiltonian
