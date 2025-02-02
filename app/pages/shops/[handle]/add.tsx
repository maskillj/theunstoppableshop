import { useRouter } from 'next/router'
import { useEffect, useState } from 'react'
import { TextInput, TextArea, NumberInput, Toggle } from '../../../components/Inputs'
import { FileUpload } from "../../../components/FileUpload"
import Image from 'next/image'
import Link from 'next/link'
import { Spinner, Button } from '../../../components/UIComp'
import { effectivePrice, encryptFile, encryptStr, sendToEstuary, trimString, zipFiles } from '../../../lib/utils'
import { useMetaMask } from 'metamask-react'
import { useApiPublicKey, useCachedPublicKey, useGuild, useIPFS, useShopId } from '../../../lib/hooks'
import { addProduct } from '../../../lib/contractCalls'

export default function AddProduct() {
  const router = useRouter()
  const { handle } = router.query
  const { account, ethereum } = useMetaMask()
  const { data: shopId, error: shopIdError } = useShopId(handle as string)
  const { data: cachedPubKey, error: cachedPubKeyError } = useCachedPublicKey(account)
  const { data: apiPubKey, error: apiPubKeyError } = useApiPublicKey()
  const { data: guildInfo, error: guildInfoError } = useGuild()

  const [productCreated, setProductCreated] = useState(false)

  const [descCID, setDescCID] = useState('')
  const [filesCID, setFilesCID] = useState('')

  const { data: descIPFS, error: descIPFSError } = useIPFS(descCID)
  const { data: filesIPFS, error: filesIPFSError } = useIPFS(filesCID)

  useEffect(() => {
    if (descIPFS && filesIPFS && productCreated) {
      router.push(`/shops/${handle}`)
    }
  }, [descIPFS, filesIPFS, productCreated, router, handle])


  const [name, setName] = useState<string>()
  const [description, setDescription] = useState<string>()
  const [price, setPrice] = useState<number>()
  const [stock, setStock] = useState<number>()
  const [unlimitedStock, setUnlimitedStock] = useState<boolean>(false)
  const [preview, setPreview] = useState<File[]>()
  const [previewStr, setPreviewStr] = useState<string[]>([])
  const [files, setFiles] = useState<File[]>([])

  const [loadingMsg, setLoadingMsg] = useState<string>()
  const [errorMsg, setErrorMsg] = useState<string>("Mandatory Fields (*) are not filled")

  const isValidProduct = account && name && description && (price && price > 0) && preview?.length && files.length && (stock || unlimitedStock)

  useEffect(() => {
    if (isValidProduct) {
      setErrorMsg("")
    } else {
      setErrorMsg("Mandatory Fields (*) are not filled")
    }
  }, [isValidProduct])

  useEffect(() => {
    if (preview) {
      Promise.all(preview.map(file => {
        return (new Promise((resolve, reject) => {
          const reader = new FileReader()
          reader.onload = () => {
            resolve(reader.result as string)
          }
          reader.readAsDataURL(file)
        }))
      })).then(previewStr => {
        setPreviewStr(previewStr as string[])
      })
    }
  }, [preview])

  function removePreview(index: number) {
    setPreview(preview?.filter((_, i) => i !== index))
  }

  async function initAddProduct() {
    if (!isValidProduct) return
    const productDesc = {
      name,
      description,
      preview: preview?.map(file => file.name)
    }
    setLoadingMsg("Upoading metadata to IPFS..")

    const detailsJSON = new File([JSON.stringify(productDesc)], "productDesc.json")
    const detailsFiles = [...preview, detailsJSON]

    const detailsFileName = `@${handle}-${trimString(name, 5)}-desc`
    const detailsZip = await zipFiles(detailsFiles, detailsFileName) as Blob


    const descResponse = await sendToEstuary(detailsZip, detailsFileName + '.zip')
    setLoadingMsg("Uploading encrypting files to IPFS..")
    setDescCID(descResponse.cid)

    const productFileName = `@${handle}-${trimString(name, 5)}-files`
    const productFileZip = await zipFiles(files, productFileName) as Blob

    const { data: encrypted, key: licenseKey } = await encryptFile(productFileZip)

    const productResponse = await sendToEstuary(encrypted, productFileName + '.zip')
    setLoadingMsg("Calling Contract..")
    setFilesCID(productResponse.cid)

    const lockedLicense = encryptStr(licenseKey, apiPubKey!)
    const sellerLicense = encryptStr(licenseKey, cachedPubKey!)

    const { success, error } = await addProduct(
      shopId!,
      [`${productResponse.cid},${descResponse.cid}`],
      Buffer.from(lockedLicense).toString('base64'),
      sellerLicense,
      price.toString(),
      unlimitedStock ? 4294967295 : stock!,
      '0x0000000000000000000000000000000000000000',
      0,
      '',
      ethereum
    )

    if (success) {
      setProductCreated(true)
    } else {
      setLoadingMsg("")
      setErrorMsg(error)
    }
  }

  return (
    <div className="w-[640px] m-auto my-24">
      <div className="text-2xl pl-4 mb-4 text-gray-600">Add Product</div>
      <div className="p-4 flex flex-col gap-4">
        <div className="uppercase text-xs text-gray-500 my-2">Product Information</div>
        <div className="flex flex-row text-gray-500 gap-3">
          <div className="text-sm w-56">Product Name *</div>
          <TextInput placeholder={'Product Name'} setValue={setName} />
        </div>
        <div className="flex flex-row text-gray-500 gap-3">
          <div className="text-sm w-56">Description *</div>
          <TextArea placeholder={'Product Description'} setValue={setDescription} />
        </div>
        <div className="flex flex-row text-gray-500 gap-3">
          <div className="text-sm w-56">Price *</div>
          <div>
            <NumberInput placeHolder="0.000000 MATIC" setValue={setPrice} isDecimal={true} />
            <div className="text-gray-500 text-xs mt-2 w-96">
              Effective price : <span className='text-purple-800'>
                {effectivePrice((price || 0), (guildInfo?.ratingReward || 0), (guildInfo?.serviceTax || 0))}
              </span> MATIC,  including {(guildInfo?.ratingReward || 0)} MATIC Rating Reward + {(guildInfo?.serviceTax || 0)} MATIC service fee.
            </div>
          </div>
        </div>
        <div className="flex flex-row text-gray-500 gap-3">
          <div className="text-sm w-56">Supply *</div>
          <div>
            <NumberInput placeHolder="No. of available" setValue={setStock} isDisabled={unlimitedStock} value={unlimitedStock ? '∞' : ''} />
            <Toggle label="Unlimited" checked={false} setValue={setUnlimitedStock} />
          </div>
        </div>
        <div className="flex flex-row text-gray-500 gap-3">
          <div className="text-sm w-56">Preview *</div>
          <div>
            <FileUpload files={preview} onlyImages={true} maxFiles={5} setFiles={setPreview} />
            <div className="flex flex-row gap-2 mt-2">
              {previewStr.map((file, index) =>
                <div key={index} className="group cursor-pointer" onClick={() => removePreview(index)}>
                  <div className="border rounded group-hover:border-red-500 w-[72px] h-[72px]">
                    <Image src={file} alt="" width={72} height={72} objectFit="cover" className="rounded border" placeholder="blur" blurDataURL="data:image/gif;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mN8+B8AAscB4jINlWEAAAAASUVORK5CYII=" />
                  </div>
                  <div className="text-xs text-red-700 invisible group-hover:visible text-center">Remove</div>
                </div>
              )}
              {
                new Array(5 - (previewStr || []).length).fill(0).map((_, index) =>
                  <div key={'empty-' + index} className="w-[70px] h-[70px] bg-gray-100 rounded" />)
              }
            </div>
          </div>
        </div>
        <div className="uppercase text-xs text-gray-500 my-2">Product Files</div>
        <div className="flex flex-row text-gray-500 gap-3" >
          <div className="text-sm w-56">Product Files *</div>
          <div>
            <FileUpload setFiles={setFiles} />
            <div className="text-sm text-gray-500 mt-4 mb-2 w-96 whitespace-normal">
              Uploaded Files : ({files.length})
            </div>
            <div>
              {files.map((file, i) => (<div key={'file-' + i} className="text-gray-500 text-sm my-1">{trimString(file.name, 50)}</div>))}
            </div>
          </div>
        </div>
      </div>
      <div className="flex flex-row gap-4 px-4 mt-8 mb-4 items-center">
        {loadingMsg && <Spinner msg={loadingMsg} />}
        {errorMsg && (!loadingMsg) && <div className="text-red-500 text-sm">{errorMsg}</div>}
        <Link href={`/shops/${handle}`}>
          <a className="ml-auto"><Button text="Cancel" /></a>
        </Link>
        <Button text="Add Product" isPrimary={true} isDisabled={!isValidProduct} onClick={initAddProduct} />
      </div>
    </div>
  )
}
