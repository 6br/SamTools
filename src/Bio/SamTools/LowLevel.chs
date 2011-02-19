-- -*- haskell -*-
{-# LANGUAGE ForeignFunctionInterface, EmptyDataDecls #-}

module Bio.SamTools.LowLevel ( TamFilePtr
                             , samOpen, samClose
                             , BamFilePtr
                             , bamOpen, bamClose
                             , BamHeaderPtr
                             , getNTargets, getTargetName, getTargetLen, bamGetTid
                             , samHeaderRead, samHeaderRead2                             
                             , samRead1
                             , bamHeaderRead, bamHeaderWrite
                             , bamRead1, bamWrite1
                             , Bam1CorePtr
                             , Bam1Ptr, Bam1Int
                             , bamInit1, bamDestroy1, bamDestroy1Ptr
                             , bam1QName
                             , SamFilePtr, SamFileInt
                             , sbamOpen, sbamClose, getSbamHeader, sbamRead, sbamWrite                             
                             )
where

import C2HS
import Control.Monad
import qualified Data.ByteString.Char8 as BS
import Foreign.Ptr

#include "sam.h"
#include "samtools.h"

data TamFileInt
{#pointer tamFile as TamFilePtr -> TamFileInt#}

data BamFileInt
{#pointer bamFile as BamFilePtr -> BamFileInt#}

{#fun unsafe bam_open_ as bamOpen
  { `String'
  , `String' } -> `BamFilePtr' id#}

{#fun unsafe bam_close_ as bamClose
  {id `BamFilePtr'} -> `CInt' id#}

data BamHeaderInt
{#pointer *bam_header_t as BamHeaderPtr -> BamHeaderInt#}

getNTargets :: BamHeaderPtr -> IO CInt
getNTargets = {#get bam_header_t->n_targets#}

getTargetName :: BamHeaderPtr -> IO (Ptr CString)
getTargetName = {#get bam_header_t->target_name#}

getTargetLen :: BamHeaderPtr -> IO (Ptr CUInt)
getTargetLen = {#get bam_header_t->target_len#}

newtype BamFlag = BamFlag { unBamFlag :: CUInt }
                deriving (Eq, Show, Ord)

flagPaired :: BamFlag
flagPaired = BamFlag {#call pure unsafe bam_fpaired#}

flagProperPair :: BamFlag
flagProperPair = BamFlag {#call pure unsafe bam_fproper_pair#}

flagUnmap :: BamFlag
flagUnmap = BamFlag {#call pure unsafe bam_funmap#}

flagMUnmap :: BamFlag
flagMUnmap = BamFlag {#call pure unsafe bam_fmunmap#}

flagReverse :: BamFlag
flagReverse = BamFlag {#call pure unsafe bam_freverse#}

flagMReverse :: BamFlag
flagMReverse = BamFlag {#call pure unsafe bam_fmreverse#}

flagRead1 :: BamFlag
flagRead1 = BamFlag {#call pure unsafe bam_fread1#}

flagRead2 :: BamFlag
flagRead2 = BamFlag {#call pure unsafe bam_fread2#}

flagSecondary :: BamFlag
flagSecondary = BamFlag {#call pure unsafe bam_fsecondary#}

flagQCFail :: BamFlag
flagQCFail = BamFlag {#call pure unsafe bam_fqcfail#}

flagDup :: BamFlag
flagDup = BamFlag {#call pure unsafe bam_fdup#}

newtype BamCigar = BamCigar { unBamCigar :: CUInt }
                   deriving (Eq, Show, Ord)
                            
cigarMatch :: BamCigar
cigarMatch = BamCigar {#call pure unsafe bam_cmatch#}

cigarIns :: BamCigar
cigarIns = BamCigar {#call pure unsafe bam_cins#}

cigarDel :: BamCigar
cigarDel = BamCigar {#call pure unsafe bam_cdel#}

cigarRefSkip :: BamCigar
cigarRefSkip = BamCigar {#call pure unsafe bam_cref_skip#}

cigarSoftClip :: BamCigar
cigarSoftClip = BamCigar {#call pure unsafe bam_csoft_clip#}

cigarHardClip :: BamCigar
cigarHardClip = BamCigar {#call pure unsafe bam_chard_clip#}

cigarPad :: BamCigar
cigarPad = BamCigar {#call pure unsafe bam_cpad#}

data Bam1CoreInt
{#pointer *bam1_core_t as Bam1CorePtr -> Bam1CoreInt#}

getTID :: Bam1CorePtr -> IO Int
getTID = liftM fromIntegral . {#get bam1_core_t->tid#}

getPos :: Bam1CorePtr -> IO Int
getPos = liftM fromIntegral . {#get bam1_core_t->pos#}

getFlag :: Bam1CorePtr -> IO CUInt
getFlag = {#get bam1_core_t->flag#}

getLQSeq :: Bam1CorePtr -> IO Int
getLQSeq = liftM fromIntegral . {#get bam1_core_t->l_qseq#}

getMTID :: Bam1CorePtr -> IO Int
getMTID = liftM fromIntegral . {#get bam1_core_t->mtid#}

getMPos :: Bam1CorePtr -> IO Int
getMPos = liftM fromIntegral . {#get bam1_core_t->mpos#}

getISize :: Bam1CorePtr -> IO Int
getISize = liftM fromIntegral . {#get bam1_core_t->isize#}

data Bam1Int
{#pointer *bam1_t as Bam1Ptr -> Bam1Int#}

{#fun pure unsafe bam1_strand_ as bam1Strand 
  {id `Bam1Ptr' } -> `Bool'#}

{#fun pure unsafe bam1_mstrand_ as bam1MStrand 
  {id `Bam1Ptr' } -> `Bool'#}

{#fun pure unsafe bam1_cigar_ as bam1Cigar
  {id `Bam1Ptr' } -> `Ptr CUInt' id#}

{#fun pure unsafe bam1_qname_ as bam1QName
  {id `Bam1Ptr' } -> `BS.ByteString' packCString*#}

{#fun pure unsafe bam1_seq_ as bam1Seq
  {id `Bam1Ptr' } -> `Ptr CUChar' id#}

{#fun pure unsafe bam1_qual_ as bam1Qual
  {id `Bam1Ptr' } -> `Ptr CUChar' id#}

{#fun pure unsafe bam1_seqi_ as bam1Seqi
  { id `Ptr CUChar' 
  , id `CInt' } -> `CUChar' id#}

-- Low-level SAM I/O

{#fun unsafe sam_open as samOpen
  {`String'} -> `TamFilePtr' id#}

{#fun unsafe sam_close as samClose
  {id `TamFilePtr'} -> `()'#}

{#fun unsafe sam_read1 as samRead1
  { id `TamFilePtr'
  , id `BamHeaderPtr'
  , id `Bam1Ptr' } -> `Int' #}

{#fun unsafe sam_header_read2 as samHeaderRead2
  {`String'} -> `BamHeaderPtr' id#}

{#fun unsafe sam_header_read as samHeaderRead
  {id `TamFilePtr'} -> `BamHeaderPtr' id#}

{#fun unsafe bam_get_tid as bamGetTid
  { id `BamHeaderPtr'
  , useAsCString* `BS.ByteString'} -> `Int'#}

-- Low-level BAM I/O
{#fun unsafe bam_header_init as bamHeaderInit
  { } -> `BamHeaderPtr' id#}

{#fun unsafe bam_header_destroy as bamHeaderDestroy
  {id `BamHeaderPtr' } -> `()'#}

{#fun unsafe bam_header_read as bamHeaderRead
  {id `BamFilePtr'} -> `BamHeaderPtr' id#}

{#fun unsafe bam_header_write as bamHeaderWrite
  { id `BamFilePtr'
  , id `BamHeaderPtr' } -> `CInt' id#}

{#fun unsafe bam_read1 as bamRead1
  { id `BamFilePtr' 
  , id `Bam1Ptr' } -> `CInt' id#}

{#fun unsafe bam_write1 as bamWrite1
  { id `BamFilePtr' 
  , id `Bam1Ptr' } -> `CInt' id#}

{#fun unsafe bam_init1_ as bamInit1
  { } -> `Bam1Ptr' id#}

{#fun unsafe bam_destroy1_ as bamDestroy1
  { id `Bam1Ptr' } -> `()'#}

foreign import ccall unsafe "samtools.h &bam_destroy1_" bamDestroy1Ptr :: FunPtr (Ptr Bam1Int -> IO ())

-- Unified SAM/BAM I/O

data SamFileInt
{#pointer *samfile_t as SamFilePtr -> SamFileInt#}

getSbamHeader :: SamFilePtr -> IO BamHeaderPtr
getSbamHeader = {#get samfile_t->header#}

{#fun unsafe samopen as sbamOpen
  { `String'
  , `String'
  , id `Ptr ()' } -> `SamFilePtr' id#}
    
{#fun unsafe samclose as sbamClose
  { id `SamFilePtr' } -> `()'#}

{#fun unsafe samread as sbamRead
  { id `SamFilePtr'
  , id `Bam1Ptr' } -> `CInt' id#}

{#fun unsafe samwrite as sbamWrite
  { id `SamFilePtr'
  , id `Bam1Ptr' } -> `CInt' id#}

-- Helpers

packCString = BS.packCString
useAsCString = BS.useAsCString

